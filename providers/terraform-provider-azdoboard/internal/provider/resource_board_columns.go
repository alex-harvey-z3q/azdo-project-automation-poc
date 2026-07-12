package provider

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/hashicorp/terraform-plugin-framework/diag"
	"github.com/hashicorp/terraform-plugin-framework/resource"
	"github.com/hashicorp/terraform-plugin-framework/resource/schema"
	"github.com/hashicorp/terraform-plugin-framework/types"
)

var _ resource.Resource = (*boardColumnsResource)(nil)
var _ resource.ResourceWithConfigure = (*boardColumnsResource)(nil)

type boardColumnsResource struct {
	client *azureDevOpsClient
}

type boardColumnsResourceModel struct {
	ID      types.String  `tfsdk:"id"`
	Project types.String  `tfsdk:"project"`
	Team    types.String  `tfsdk:"team"`
	Board   types.String  `tfsdk:"board"`
	Columns []columnModel `tfsdk:"columns"`
}

type columnModel struct {
	Name          types.String `tfsdk:"name"`
	StateMappings types.Map    `tfsdk:"state_mappings"`
	ColumnType    types.String `tfsdk:"column_type"`
	ItemLimit     types.Int64  `tfsdk:"item_limit"`
	IsSplit       types.Bool   `tfsdk:"is_split"`
	Description   types.String `tfsdk:"description"`
}

type boardColumn struct {
	ID            string            `json:"id,omitempty"`
	Name          string            `json:"name"`
	StateMappings map[string]string `json:"stateMappings,omitempty"`
	ColumnType    string            `json:"columnType,omitempty"`
	ItemLimit     int64             `json:"itemLimit,omitempty"`
	IsSplit       bool              `json:"isSplit,omitempty"`
	Description   string            `json:"description,omitempty"`
}

type boardColumnsResponse struct {
	Count int           `json:"count"`
	Value []boardColumn `json:"value"`
}

func NewBoardColumnsResource() resource.Resource {
	return &boardColumnsResource{}
}

func (r *boardColumnsResource) Metadata(_ context.Context, req resource.MetadataRequest, resp *resource.MetadataResponse) {
	resp.TypeName = req.ProviderTypeName + "_board_columns"
}

func (r *boardColumnsResource) Schema(_ context.Context, _ resource.SchemaRequest, resp *resource.SchemaResponse) {
	resp.Schema = schema.Schema{
		MarkdownDescription: "Manages the columns for an existing Azure DevOps team board. The board itself is created by Azure DevOps from the project process and team.",
		Attributes: map[string]schema.Attribute{
			"id": schema.StringAttribute{
				Computed:            true,
				MarkdownDescription: "Synthetic Terraform ID in the form `project/team/board`.",
			},
			"project": schema.StringAttribute{
				Required:            true,
				MarkdownDescription: "Azure DevOps project name.",
			},
			"team": schema.StringAttribute{
				Required:            true,
				MarkdownDescription: "Azure DevOps team name.",
			},
			"board": schema.StringAttribute{
				Required:            true,
				MarkdownDescription: "Board name, for example `Issues`, `Stories`, or `Backlog items` depending on the process template.",
			},
			"columns": schema.ListNestedAttribute{
				Required:            true,
				MarkdownDescription: "Ordered board columns.",
				NestedObject: schema.NestedAttributeObject{
					Attributes: map[string]schema.Attribute{
						"name": schema.StringAttribute{
							Required: true,
						},
						"state_mappings": schema.MapAttribute{
							ElementType:         types.StringType,
							Required:            true,
							MarkdownDescription: "Mapping from work item type to workflow state, for example `{ Issue = \"To Do\" }` for Basic or `{ \"User Story\" = \"New\" }` for Agile.",
						},
						"column_type": schema.StringAttribute{
							Optional:            true,
							MarkdownDescription: "Azure DevOps column type. Common values are `incoming`, `inProgress`, and `outgoing`.",
						},
						"item_limit": schema.Int64Attribute{
							Optional:            true,
							MarkdownDescription: "Optional work-in-progress limit.",
						},
						"is_split": schema.BoolAttribute{
							Optional:            true,
							MarkdownDescription: "Whether the board column is split into doing/done lanes.",
						},
						"description": schema.StringAttribute{
							Optional: true,
						},
					},
				},
			},
		},
	}
}

func (r *boardColumnsResource) Configure(_ context.Context, req resource.ConfigureRequest, resp *resource.ConfigureResponse) {
	if req.ProviderData == nil {
		return
	}

	client, ok := req.ProviderData.(*azureDevOpsClient)
	if !ok {
		resp.Diagnostics.AddError("Unexpected provider data", fmt.Sprintf("Expected *azureDevOpsClient, got %T.", req.ProviderData))
		return
	}

	r.client = client
}

func (r *boardColumnsResource) Create(ctx context.Context, req resource.CreateRequest, resp *resource.CreateResponse) {
	var plan boardColumnsResourceModel
	resp.Diagnostics.Append(req.Plan.Get(ctx, &plan)...)
	if resp.Diagnostics.HasError() {
		return
	}

	updated, diagnostics := r.putColumns(ctx, plan)
	resp.Diagnostics.Append(diagnostics...)
	if resp.Diagnostics.HasError() {
		return
	}

	plan.ID = resourceID(plan)
	plan.Columns = updated
	resp.Diagnostics.Append(resp.State.Set(ctx, &plan)...)
}

func (r *boardColumnsResource) Read(ctx context.Context, req resource.ReadRequest, resp *resource.ReadResponse) {
	var state boardColumnsResourceModel
	resp.Diagnostics.Append(req.State.Get(ctx, &state)...)
	if resp.Diagnostics.HasError() {
		return
	}

	columns, err := r.getColumns(ctx, state.Project.ValueString(), state.Team.ValueString(), state.Board.ValueString(), state.Columns)
	if err != nil {
		resp.Diagnostics.AddError("Read Azure DevOps board columns failed", err.Error())
		return
	}

	state.Columns = columns

	resp.Diagnostics.Append(resp.State.Set(ctx, &state)...)
}

func (r *boardColumnsResource) Update(ctx context.Context, req resource.UpdateRequest, resp *resource.UpdateResponse) {
	var plan boardColumnsResourceModel
	resp.Diagnostics.Append(req.Plan.Get(ctx, &plan)...)
	if resp.Diagnostics.HasError() {
		return
	}

	updated, diagnostics := r.putColumns(ctx, plan)
	resp.Diagnostics.Append(diagnostics...)
	if resp.Diagnostics.HasError() {
		return
	}

	plan.ID = resourceID(plan)
	plan.Columns = updated
	resp.Diagnostics.Append(resp.State.Set(ctx, &plan)...)
}

func (r *boardColumnsResource) Delete(ctx context.Context, req resource.DeleteRequest, resp *resource.DeleteResponse) {
	var state boardColumnsResourceModel
	resp.Diagnostics.Append(req.State.Get(ctx, &state)...)
	if resp.Diagnostics.HasError() {
		return
	}

	resp.Diagnostics.AddWarning(
		"Removing board columns from Terraform state only",
		"Azure DevOps boards are built-in team surfaces. This provider does not delete or reset the remote board columns on resource deletion.",
	)
	resp.State.RemoveResource(ctx)
}

func (r *boardColumnsResource) putColumns(ctx context.Context, plan boardColumnsResourceModel) ([]columnModel, diag.Diagnostics) {
	var diagnostics diag.Diagnostics

	currentColumns, err := r.getRawColumns(ctx, plan.Project.ValueString(), plan.Team.ValueString(), plan.Board.ValueString())
	if err != nil {
		diagnostics.AddError("Read current Azure DevOps board columns failed", err.Error())
		return nil, diagnostics
	}

	currentByName := make(map[string]boardColumn, len(currentColumns))
	for _, column := range currentColumns {
		currentByName[column.Name] = column
	}

	desiredColumns := make([]boardColumn, 0, len(plan.Columns))
	for _, column := range plan.Columns {
		stateMappings := map[string]string{}
		diagnostics.Append(column.StateMappings.ElementsAs(ctx, &stateMappings, false)...)
		if diagnostics.HasError() {
			return nil, diagnostics
		}

		desired := boardColumn{
			Name:          column.Name.ValueString(),
			StateMappings: stateMappings,
			ColumnType:    stringWithDefault(column.ColumnType, "inProgress"),
			ItemLimit:     int64WithDefault(column.ItemLimit, 0),
			IsSplit:       boolWithDefault(column.IsSplit, false),
			Description:   stringWithDefault(column.Description, ""),
		}

		if current, ok := currentByName[desired.Name]; ok {
			desired.ID = current.ID
		}

		desiredColumns = append(desiredColumns, desired)
	}

	path := boardColumnsPath(plan.Project.ValueString(), plan.Team.ValueString(), plan.Board.ValueString())
	var response boardColumnsResponse
	if err := r.client.do(ctx, http.MethodPut, path, desiredColumns, &response); err != nil {
		diagnostics.AddError("Update Azure DevOps board columns failed", err.Error())
		return nil, diagnostics
	}

	return columnsToModel(ctx, response.Value, plan.Columns, &diagnostics), diagnostics
}

func (r *boardColumnsResource) getColumns(ctx context.Context, project string, team string, board string, prior []columnModel) ([]columnModel, error) {
	var diagnostics diag.Diagnostics
	columns, err := r.getRawColumns(ctx, project, team, board)
	if err != nil {
		return nil, err
	}

	models := columnsToModel(ctx, columns, prior, &diagnostics)
	if diagnostics.HasError() {
		return nil, fmt.Errorf("convert board columns into Terraform state: %s", diagnostics.Errors()[0].Detail())
	}

	return models, nil
}

func (r *boardColumnsResource) getRawColumns(ctx context.Context, project string, team string, board string) ([]boardColumn, error) {
	path := boardColumnsPath(project, team, board)
	var response boardColumnsResponse
	if err := r.client.do(ctx, http.MethodGet, path, nil, &response); err != nil {
		return nil, err
	}

	if response.Value != nil {
		return response.Value, nil
	}

	var direct []boardColumn
	raw, err := json.Marshal(response)
	if err != nil {
		return nil, err
	}
	if err := json.Unmarshal(raw, &direct); err != nil {
		return nil, err
	}

	return direct, nil
}

func columnsToModel(ctx context.Context, columns []boardColumn, prior []columnModel, diagnostics *diag.Diagnostics) []columnModel {
	priorByName := make(map[string]columnModel, len(prior))
	for _, column := range prior {
		if !column.Name.IsNull() && !column.Name.IsUnknown() {
			priorByName[column.Name.ValueString()] = column
		}
	}

	result := make([]columnModel, 0, len(columns))
	for _, column := range columns {
		stateMappings, diags := types.MapValueFrom(ctx, types.StringType, column.StateMappings)
		diagnostics.Append(diags...)
		if diagnostics.HasError() {
			return nil
		}

		model := columnModel{
			Name:          types.StringValue(column.Name),
			StateMappings: stateMappings,
			ColumnType:    nullableString(column.ColumnType),
			ItemLimit:     nullableInt64(column.ItemLimit),
			IsSplit:       nullableBool(column.IsSplit),
			Description:   nullableString(column.Description),
		}

		if priorColumn, ok := priorByName[column.Name]; ok {
			model.ColumnType = preserveStringNull(priorColumn.ColumnType, model.ColumnType)
			model.ItemLimit = preserveInt64Null(priorColumn.ItemLimit, model.ItemLimit)
			model.IsSplit = preserveBoolNull(priorColumn.IsSplit, model.IsSplit)
			model.Description = preserveStringNull(priorColumn.Description, model.Description)
		}

		result = append(result, model)
	}

	return result
}

func resourceID(model boardColumnsResourceModel) types.String {
	return types.StringValue(fmt.Sprintf("%s/%s/%s", model.Project.ValueString(), model.Team.ValueString(), model.Board.ValueString()))
}

func stringWithDefault(value types.String, fallback string) string {
	if value.IsNull() || value.IsUnknown() {
		return fallback
	}
	return value.ValueString()
}

func int64WithDefault(value types.Int64, fallback int64) int64 {
	if value.IsNull() || value.IsUnknown() {
		return fallback
	}
	return value.ValueInt64()
}

func boolWithDefault(value types.Bool, fallback bool) bool {
	if value.IsNull() || value.IsUnknown() {
		return fallback
	}
	return value.ValueBool()
}

func stringDefault(value string, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}

func nullableString(value string) types.String {
	if value == "" {
		return types.StringNull()
	}
	return types.StringValue(value)
}

func nullableInt64(value int64) types.Int64 {
	if value == 0 {
		return types.Int64Null()
	}
	return types.Int64Value(value)
}

func nullableBool(value bool) types.Bool {
	if !value {
		return types.BoolNull()
	}
	return types.BoolValue(value)
}

func preserveStringNull(prior types.String, current types.String) types.String {
	if prior.IsUnknown() {
		return current
	}
	return prior
}

func preserveInt64Null(prior types.Int64, current types.Int64) types.Int64 {
	if prior.IsUnknown() {
		return current
	}
	return prior
}

func preserveBoolNull(prior types.Bool, current types.Bool) types.Bool {
	if prior.IsUnknown() {
		return current
	}
	return prior
}
