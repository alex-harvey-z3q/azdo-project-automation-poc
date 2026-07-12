package provider

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"github.com/hashicorp/terraform-plugin-framework/diag"
	"github.com/hashicorp/terraform-plugin-framework/resource"
	"github.com/hashicorp/terraform-plugin-framework/resource/schema"
	"github.com/hashicorp/terraform-plugin-framework/types"
)

var _ resource.Resource = (*teamSettingsResource)(nil)
var _ resource.ResourceWithConfigure = (*teamSettingsResource)(nil)

type teamSettingsResource struct {
	client *azureDevOpsClient
}

type teamSettingsResourceModel struct {
	ID                    types.String `tfsdk:"id"`
	Project               types.String `tfsdk:"project"`
	Team                  types.String `tfsdk:"team"`
	DefaultAreaPath       types.String `tfsdk:"default_area_path"`
	IncludeAreaChildren   types.Bool   `tfsdk:"include_area_children"`
	BacklogIterationPath  types.String `tfsdk:"backlog_iteration_path"`
	DefaultIterationMacro types.String `tfsdk:"default_iteration_macro"`
}

type iterationClassificationNode struct {
	ID         json.RawMessage `json:"id"`
	Identifier string          `json:"identifier"`
	Name       string          `json:"name"`
	Path       string          `json:"path"`
}

type teamSettingsPatch struct {
	BacklogIteration      string `json:"backlogIteration,omitempty"`
	DefaultIterationMacro string `json:"defaultIterationMacro,omitempty"`
}

type teamFieldValuesPatch struct {
	DefaultValue string                `json:"defaultValue"`
	Values       []teamFieldValuePatch `json:"values"`
}

type teamFieldValuePatch struct {
	Value           string `json:"value"`
	IncludeChildren bool   `json:"includeChildren"`
}

func NewTeamSettingsResource() resource.Resource {
	return &teamSettingsResource{}
}

func (r *teamSettingsResource) Metadata(_ context.Context, req resource.MetadataRequest, resp *resource.MetadataResponse) {
	resp.TypeName = req.ProviderTypeName + "_team_settings"
}

func (r *teamSettingsResource) Schema(_ context.Context, _ resource.SchemaRequest, resp *resource.SchemaResponse) {
	resp.Schema = schema.Schema{
		MarkdownDescription: "Configures Azure DevOps team settings needed before board column settings can be managed.",
		Attributes: map[string]schema.Attribute{
			"id": schema.StringAttribute{
				Computed:            true,
				MarkdownDescription: "Synthetic Terraform ID in the form `project/team/settings`.",
			},
			"project": schema.StringAttribute{
				Required:            true,
				MarkdownDescription: "Azure DevOps project name.",
			},
			"team": schema.StringAttribute{
				Required:            true,
				MarkdownDescription: "Azure DevOps team name.",
			},
			"default_area_path": schema.StringAttribute{
				Optional:            true,
				MarkdownDescription: "Default Area Path for the team field. Defaults to the project root Area Path.",
			},
			"include_area_children": schema.BoolAttribute{
				Optional:            true,
				MarkdownDescription: "Whether the team field should include child Area Paths. Defaults to true.",
			},
			"backlog_iteration_path": schema.StringAttribute{
				Required:            true,
				MarkdownDescription: "Iteration path to use as the team backlog iteration. Use the project name for the root iteration.",
			},
			"default_iteration_macro": schema.StringAttribute{
				Optional:            true,
				MarkdownDescription: "Default iteration macro. A common value is `@CurrentIteration`.",
			},
		},
	}
}

func (r *teamSettingsResource) Configure(_ context.Context, req resource.ConfigureRequest, resp *resource.ConfigureResponse) {
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

func (r *teamSettingsResource) Create(ctx context.Context, req resource.CreateRequest, resp *resource.CreateResponse) {
	var plan teamSettingsResourceModel
	resp.Diagnostics.Append(req.Plan.Get(ctx, &plan)...)
	if resp.Diagnostics.HasError() {
		return
	}

	resp.Diagnostics.Append(r.putTeamSettings(ctx, plan)...)
	if resp.Diagnostics.HasError() {
		return
	}

	plan.ID = teamSettingsID(plan)
	resp.Diagnostics.Append(resp.State.Set(ctx, &plan)...)
}

func (r *teamSettingsResource) Read(ctx context.Context, req resource.ReadRequest, resp *resource.ReadResponse) {
	var state teamSettingsResourceModel
	resp.Diagnostics.Append(req.State.Get(ctx, &state)...)
	if resp.Diagnostics.HasError() {
		return
	}

	state.ID = teamSettingsID(state)
	resp.Diagnostics.Append(resp.State.Set(ctx, &state)...)
}

func (r *teamSettingsResource) Update(ctx context.Context, req resource.UpdateRequest, resp *resource.UpdateResponse) {
	var plan teamSettingsResourceModel
	resp.Diagnostics.Append(req.Plan.Get(ctx, &plan)...)
	if resp.Diagnostics.HasError() {
		return
	}

	resp.Diagnostics.Append(r.putTeamSettings(ctx, plan)...)
	if resp.Diagnostics.HasError() {
		return
	}

	plan.ID = teamSettingsID(plan)
	resp.Diagnostics.Append(resp.State.Set(ctx, &plan)...)
}

func (r *teamSettingsResource) Delete(ctx context.Context, req resource.DeleteRequest, resp *resource.DeleteResponse) {
	resp.Diagnostics.AddWarning(
		"Removing team settings from Terraform state only",
		"Azure DevOps team settings are built-in team configuration. This provider does not reset remote team settings on resource deletion.",
	)
	resp.State.RemoveResource(ctx)
}

func (r *teamSettingsResource) putTeamSettings(ctx context.Context, plan teamSettingsResourceModel) diag.Diagnostics {
	var diagnostics diag.Diagnostics

	if err := r.putTeamFieldValues(ctx, plan); err != nil {
		diagnostics.AddError("Update Azure DevOps team field values failed", err.Error())
		return diagnostics
	}

	iterationID, err := r.resolveIterationID(ctx, plan.Project.ValueString(), plan.BacklogIterationPath.ValueString())
	if err != nil {
		diagnostics.AddError("Resolve Azure DevOps backlog iteration failed", err.Error())
		return diagnostics
	}

	patch := teamSettingsPatch{
		BacklogIteration:      iterationID,
		DefaultIterationMacro: stringWithDefault(plan.DefaultIterationMacro, "@CurrentIteration"),
	}

	path := teamSettingsPath(plan.Project.ValueString(), plan.Team.ValueString())
	if err := r.client.do(ctx, http.MethodPatch, path, patch, nil); err != nil {
		diagnostics.AddError("Update Azure DevOps team settings failed", err.Error())
		return diagnostics
	}

	return diagnostics
}

func (r *teamSettingsResource) putTeamFieldValues(ctx context.Context, plan teamSettingsResourceModel) error {
	defaultAreaPath := stringWithDefault(plan.DefaultAreaPath, plan.Project.ValueString())
	includeAreaChildren := boolWithDefault(plan.IncludeAreaChildren, true)

	patch := teamFieldValuesPatch{
		DefaultValue: defaultAreaPath,
		Values: []teamFieldValuePatch{
			{
				Value:           defaultAreaPath,
				IncludeChildren: includeAreaChildren,
			},
		},
	}

	path := teamFieldValuesPath(plan.Project.ValueString(), plan.Team.ValueString())
	return r.client.do(ctx, http.MethodPatch, path, patch, nil)
}

func (r *teamSettingsResource) resolveIterationID(ctx context.Context, project string, iterationPath string) (string, error) {
	path := iterationClassificationNodePath(project, iterationPath)
	var node iterationClassificationNode
	if err := r.client.do(ctx, http.MethodGet, path, nil, &node); err != nil {
		return "", err
	}
	if node.Identifier != "" {
		return node.Identifier, nil
	}

	id := strings.Trim(string(node.ID), `"`)
	if id == "" || id == "null" {
		return "", fmt.Errorf("iteration path %q did not return an id or identifier", iterationPath)
	}
	return id, nil
}

func teamSettingsID(model teamSettingsResourceModel) types.String {
	return types.StringValue(fmt.Sprintf("%s/%s/settings", model.Project.ValueString(), model.Team.ValueString()))
}
