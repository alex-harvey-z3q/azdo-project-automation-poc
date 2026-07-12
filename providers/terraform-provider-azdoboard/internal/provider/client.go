package provider

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type azureDevOpsClient struct {
	baseURL             string
	personalAccessToken string
	httpClient          *http.Client
}

func newAzureDevOpsClient(orgServiceURL string, personalAccessToken string) (*azureDevOpsClient, error) {
	orgServiceURL = strings.TrimRight(orgServiceURL, "/")
	parsed, err := url.Parse(orgServiceURL)
	if err != nil {
		return nil, fmt.Errorf("parse org_service_url: %w", err)
	}
	if parsed.Scheme != "https" || parsed.Host != "dev.azure.com" || strings.Trim(parsed.Path, "/") == "" {
		return nil, fmt.Errorf("org_service_url must look like https://dev.azure.com/{organization}")
	}

	return &azureDevOpsClient{
		baseURL:             orgServiceURL,
		personalAccessToken: personalAccessToken,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}, nil
}

func (c *azureDevOpsClient) do(ctx context.Context, method string, path string, input any, output any) error {
	var body io.Reader
	if input != nil {
		payload, err := json.Marshal(input)
		if err != nil {
			return fmt.Errorf("encode request body: %w", err)
		}
		body = bytes.NewReader(payload)
	}

	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, body)
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}

	token := base64.StdEncoding.EncodeToString([]byte(":" + c.personalAccessToken))
	req.Header.Set("Authorization", "Basic "+token)
	req.Header.Set("Accept", "application/json")
	if input != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("send request: %w", err)
	}
	defer resp.Body.Close()

	responseBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("read response body: %w", err)
	}

	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return fmt.Errorf("%s %s failed with %s: %s", method, path, resp.Status, strings.TrimSpace(string(responseBody)))
	}

	if output == nil || len(responseBody) == 0 {
		return nil
	}

	if err := json.Unmarshal(responseBody, output); err != nil {
		return fmt.Errorf("decode response body: %w", err)
	}

	return nil
}

func boardColumnsPath(project string, team string, board string) string {
	return fmt.Sprintf(
		"/%s/%s/_apis/work/boards/%s/columns?api-version=7.1-preview.1",
		url.PathEscape(project),
		url.PathEscape(team),
		url.PathEscape(board),
	)
}

func teamSettingsPath(project string, team string) string {
	return fmt.Sprintf(
		"/%s/%s/_apis/work/teamsettings?api-version=7.1-preview.1",
		url.PathEscape(project),
		url.PathEscape(team),
	)
}

func teamFieldValuesPath(project string, team string) string {
	return fmt.Sprintf(
		"/%s/%s/_apis/work/teamsettings/teamfieldvalues?api-version=7.1-preview.1",
		url.PathEscape(project),
		url.PathEscape(team),
	)
}

func iterationClassificationNodePath(project string, iterationPath string) string {
	relativePath := strings.TrimSpace(iterationPath)
	projectPrefix := project + "\\"
	if relativePath == project {
		relativePath = ""
	} else {
		relativePath = strings.TrimPrefix(relativePath, projectPrefix)
	}

	if relativePath == "" {
		return fmt.Sprintf(
			"/%s/_apis/wit/classificationnodes/iterations?api-version=7.1",
			url.PathEscape(project),
		)
	}

	segments := strings.Split(relativePath, "\\")
	escapedSegments := make([]string, 0, len(segments))
	for _, segment := range segments {
		escapedSegments = append(escapedSegments, url.PathEscape(segment))
	}

	return fmt.Sprintf(
		"/%s/_apis/wit/classificationnodes/iterations/%s?api-version=7.1",
		url.PathEscape(project),
		strings.Join(escapedSegments, "/"),
	)
}
