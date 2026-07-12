package provider

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"testing"
	"time"

	"github.com/hashicorp/terraform-plugin-framework/types"
)

func TestBoardColumnsPathEscapesSegments(t *testing.T) {
	got := boardColumnsPath("Project Space", "Team/A", "Backlog items")
	want := "/Project%20Space/Team%2FA/_apis/work/boards/Backlog%20items/columns?api-version=7.1-preview.1"

	if got != want {
		t.Fatalf("boardColumnsPath() = %q, want %q", got, want)
	}
}

func TestGetRawColumnsDecodesAzureDevOpsCollectionResponse(t *testing.T) {
	client, requests := newTestAzureDevOpsClient(t, func(r *http.Request) *http.Response {
		if r.Method != http.MethodGet {
			t.Fatalf("method = %s, want GET", r.Method)
		}

		return jsonResponse(t, http.StatusOK, boardColumnsResponse{
			Count: 2,
			Value: []boardColumn{
				{
					ID:            "todo-id",
					Name:          "To Do",
					ColumnType:    "incoming",
					StateMappings: map[string]string{"Issue": "To Do"},
				},
				{
					ID:            "doing-id",
					Name:          "Doing",
					ColumnType:    "inProgress",
					ItemLimit:     5,
					IsSplit:       true,
					StateMappings: map[string]string{"Issue": "Doing"},
				},
			},
		})
	})

	resource := boardColumnsResource{client: client}
	columns, err := resource.getRawColumns(context.Background(), "project", "Platform", "Issues")
	if err != nil {
		t.Fatalf("getRawColumns() error = %v", err)
	}

	if *requests != 1 {
		t.Fatalf("requests = %d, want 1", *requests)
	}
	if len(columns) != 2 {
		t.Fatalf("len(columns) = %d, want 2", len(columns))
	}
	if columns[1].ID != "doing-id" || columns[1].ItemLimit != 5 || !columns[1].IsSplit {
		t.Fatalf("columns[1] = %#v, want decoded Doing column", columns[1])
	}
}

func TestPutColumnsPreservesExistingIDsAndDecodesCollectionResponse(t *testing.T) {
	var requests *int
	client, requestCounter := newTestAzureDevOpsClient(t, func(r *http.Request) *http.Response {
		requestNumber := *requests + 1

		switch requestNumber {
		case 1:
			if r.Method != http.MethodGet {
				t.Fatalf("request 1 method = %s, want GET", r.Method)
			}

			return jsonResponse(t, http.StatusOK, boardColumnsResponse{
				Count: 1,
				Value: []boardColumn{
					{
						ID:            "existing-doing-id",
						Name:          "Doing",
						ColumnType:    "inProgress",
						StateMappings: map[string]string{"Issue": "Doing"},
					},
				},
			})
		case 2:
			if r.Method != http.MethodPut {
				t.Fatalf("request 2 method = %s, want PUT", r.Method)
			}

			var payload []boardColumn
			if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
				t.Fatalf("decode PUT payload: %v", err)
			}
			if len(payload) != 1 {
				t.Fatalf("len(payload) = %d, want 1", len(payload))
			}
			if payload[0].ID != "existing-doing-id" {
				t.Fatalf("payload[0].ID = %q, want existing-doing-id", payload[0].ID)
			}

			return jsonResponse(t, http.StatusOK, boardColumnsResponse{
				Count: 1,
				Value: []boardColumn{
					{
						ID:            "existing-doing-id",
						Name:          "Doing",
						ColumnType:    "inProgress",
						ItemLimit:     5,
						IsSplit:       true,
						StateMappings: map[string]string{"Issue": "Doing"},
					},
				},
			})
		default:
			t.Fatalf("unexpected request %d", requestNumber)
		}
		return nil
	})
	requests = requestCounter

	stateMappings, diags := types.MapValueFrom(context.Background(), types.StringType, map[string]string{"Issue": "Doing"})
	if diags.HasError() {
		t.Fatalf("create state mappings diagnostics: %v", diags)
	}

	resource := boardColumnsResource{client: client}
	columns, diagnostics := resource.putColumns(context.Background(), boardColumnsResourceModel{
		Project: types.StringValue("project"),
		Team:    types.StringValue("Platform"),
		Board:   types.StringValue("Issues"),
		Columns: []columnModel{
			{
				Name:          types.StringValue("Doing"),
				StateMappings: stateMappings,
				ColumnType:    types.StringValue("inProgress"),
				ItemLimit:     types.Int64Value(5),
				IsSplit:       types.BoolValue(true),
			},
		},
	})
	if diagnostics.HasError() {
		t.Fatalf("putColumns() diagnostics = %v", diagnostics)
	}

	if len(columns) != 1 {
		t.Fatalf("len(columns) = %d, want 1", len(columns))
	}
	if columns[0].Name.ValueString() != "Doing" || columns[0].ItemLimit.ValueInt64() != 5 {
		t.Fatalf("columns[0] = %#v, want returned Doing model", columns[0])
	}
	if *requests != 2 {
		t.Fatalf("requests = %d, want 2", *requests)
	}
}

func TestPutColumnsPreservesOmittedOptionalFieldsAsNull(t *testing.T) {
	var requests *int
	client, requestCounter := newTestAzureDevOpsClient(t, func(r *http.Request) *http.Response {
		requestNumber := *requests + 1

		switch requestNumber {
		case 1:
			return jsonResponse(t, http.StatusOK, boardColumnsResponse{
				Count: 1,
				Value: []boardColumn{
					{
						ID:            "todo-id",
						Name:          "To Do",
						StateMappings: map[string]string{"Issue": "To Do"},
					},
				},
			})
		case 2:
			return jsonResponse(t, http.StatusOK, boardColumnsResponse{
				Count: 1,
				Value: []boardColumn{
					{
						ID:            "todo-id",
						Name:          "To Do",
						ColumnType:    "incoming",
						ItemLimit:     0,
						IsSplit:       false,
						Description:   "",
						StateMappings: map[string]string{"Issue": "To Do"},
					},
				},
			})
		default:
			t.Fatalf("unexpected request %d", requestNumber)
		}
		return nil
	})
	requests = requestCounter

	stateMappings, diags := types.MapValueFrom(context.Background(), types.StringType, map[string]string{"Issue": "To Do"})
	if diags.HasError() {
		t.Fatalf("create state mappings diagnostics: %v", diags)
	}

	resource := boardColumnsResource{client: client}
	columns, diagnostics := resource.putColumns(context.Background(), boardColumnsResourceModel{
		Project: types.StringValue("project"),
		Team:    types.StringValue("Platform"),
		Board:   types.StringValue("Issues"),
		Columns: []columnModel{
			{
				Name:          types.StringValue("To Do"),
				StateMappings: stateMappings,
				ColumnType:    types.StringValue("incoming"),
				ItemLimit:     types.Int64Null(),
				IsSplit:       types.BoolNull(),
				Description:   types.StringNull(),
			},
		},
	})
	if diagnostics.HasError() {
		t.Fatalf("putColumns() diagnostics = %v", diagnostics)
	}

	if len(columns) != 1 {
		t.Fatalf("len(columns) = %d, want 1", len(columns))
	}
	if !columns[0].ItemLimit.IsNull() {
		t.Fatalf("item_limit = %#v, want null", columns[0].ItemLimit)
	}
	if !columns[0].IsSplit.IsNull() {
		t.Fatalf("is_split = %#v, want null", columns[0].IsSplit)
	}
	if !columns[0].Description.IsNull() {
		t.Fatalf("description = %#v, want null", columns[0].Description)
	}
}

func newTestAzureDevOpsClient(t *testing.T, handler func(*http.Request) *http.Response) (*azureDevOpsClient, *int) {
	t.Helper()

	requests := 0

	return &azureDevOpsClient{
		baseURL:             "https://dev.azure.com/test-org",
		personalAccessToken: "test-token",
		httpClient: &http.Client{
			Timeout: 2 * time.Second,
			Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
				response := handler(req)
				requests++
				return response, nil
			}),
		},
	}, &requests
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(req *http.Request) (*http.Response, error) {
	return f(req)
}

func jsonResponse(t *testing.T, statusCode int, value any) *http.Response {
	t.Helper()

	var body bytes.Buffer
	if err := json.NewEncoder(&body).Encode(value); err != nil {
		t.Fatalf("encode response: %v", err)
	}

	return &http.Response{
		StatusCode: statusCode,
		Status:     http.StatusText(statusCode),
		Header:     http.Header{"Content-Type": []string{"application/json"}},
		Body:       io.NopCloser(&body),
	}
}
