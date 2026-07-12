package provider

import (
	"context"
	"os"

	"github.com/hashicorp/terraform-plugin-framework/datasource"
	"github.com/hashicorp/terraform-plugin-framework/path"
	"github.com/hashicorp/terraform-plugin-framework/provider"
	"github.com/hashicorp/terraform-plugin-framework/provider/schema"
	"github.com/hashicorp/terraform-plugin-framework/resource"
	"github.com/hashicorp/terraform-plugin-framework/types"
)

var _ provider.Provider = (*azdoBoardProvider)(nil)

type azdoBoardProvider struct{}

type azdoBoardProviderModel struct {
	OrgServiceURL       types.String `tfsdk:"org_service_url"`
	PersonalAccessToken types.String `tfsdk:"personal_access_token"`
}

func New() provider.Provider {
	return &azdoBoardProvider{}
}

func (p *azdoBoardProvider) Metadata(_ context.Context, _ provider.MetadataRequest, resp *provider.MetadataResponse) {
	resp.TypeName = "azdoboard"
}

func (p *azdoBoardProvider) Schema(_ context.Context, _ provider.SchemaRequest, resp *provider.SchemaResponse) {
	resp.Schema = schema.Schema{
		MarkdownDescription: "Small proof-of-concept provider for Azure DevOps board settings not covered by the official provider.",
		Attributes: map[string]schema.Attribute{
			"org_service_url": schema.StringAttribute{
				Optional:            true,
				MarkdownDescription: "Azure DevOps organization URL, for example `https://dev.azure.com/alexharv074`. Can also be set with `AZDOBOARD_ORG_SERVICE_URL`.",
			},
			"personal_access_token": schema.StringAttribute{
				Optional:            true,
				Sensitive:           true,
				MarkdownDescription: "Azure DevOps personal access token. Can also be set with `AZDOBOARD_PERSONAL_ACCESS_TOKEN`.",
			},
		},
	}
}

func (p *azdoBoardProvider) Configure(ctx context.Context, req provider.ConfigureRequest, resp *provider.ConfigureResponse) {
	var config azdoBoardProviderModel
	resp.Diagnostics.Append(req.Config.Get(ctx, &config)...)
	if resp.Diagnostics.HasError() {
		return
	}

	orgServiceURL := os.Getenv("AZDOBOARD_ORG_SERVICE_URL")
	if !config.OrgServiceURL.IsNull() {
		orgServiceURL = config.OrgServiceURL.ValueString()
	}

	personalAccessToken := os.Getenv("AZDOBOARD_PERSONAL_ACCESS_TOKEN")
	if !config.PersonalAccessToken.IsNull() {
		personalAccessToken = config.PersonalAccessToken.ValueString()
	}

	if orgServiceURL == "" {
		resp.Diagnostics.AddAttributeError(
			path.Root("org_service_url"),
			"Missing Azure DevOps organization URL",
			"Set org_service_url in the provider block or AZDOBOARD_ORG_SERVICE_URL in the environment.",
		)
	}
	if personalAccessToken == "" {
		resp.Diagnostics.AddAttributeError(
			path.Root("personal_access_token"),
			"Missing Azure DevOps personal access token",
			"Set personal_access_token in the provider block or AZDOBOARD_PERSONAL_ACCESS_TOKEN in the environment.",
		)
	}
	if resp.Diagnostics.HasError() {
		return
	}

	client, err := newAzureDevOpsClient(orgServiceURL, personalAccessToken)
	if err != nil {
		resp.Diagnostics.AddError("Invalid Azure DevOps provider configuration", err.Error())
		return
	}

	resp.ResourceData = client
}

func (p *azdoBoardProvider) Resources(_ context.Context) []func() resource.Resource {
	return []func() resource.Resource{
		NewTeamSettingsResource,
		NewBoardColumnsResource,
	}
}

func (p *azdoBoardProvider) DataSources(_ context.Context) []func() datasource.DataSource {
	return nil
}
