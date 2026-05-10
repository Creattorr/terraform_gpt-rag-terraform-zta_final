param(
  [Parameter(Mandatory = $true)]
  [string] $ResourceGroupName,
  [Parameter(Mandatory = $true)]
  [string] $SearchServiceName,
  [Parameter(Mandatory = $true)]
  [string] $IndexName,
  [int] $VectorDimensions = 3072,
  [string] $ApiVersion = "2025-05-01-preview"
)

$ErrorActionPreference = "Stop"

$adminKey = az search admin-key show `
  --resource-group $ResourceGroupName `
  --service-name $SearchServiceName `
  --query primaryKey `
  --output tsv

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($adminKey)) {
  throw "Unable to read AI Search admin key for $SearchServiceName."
}

$index = @{
  name = $IndexName
  fields = @(
    @{ name = "id"; type = "Edm.String"; key = $true; searchable = $false; filterable = $true; sortable = $false; facetable = $false },
    @{ name = "parent_id"; type = "Edm.String"; searchable = $false; filterable = $true; sortable = $false; facetable = $false },
    @{ name = "metadata_storage_path"; type = "Edm.String"; searchable = $false; filterable = $true; sortable = $false; facetable = $false },
    @{ name = "metadata_storage_name"; type = "Edm.String"; searchable = $true; filterable = $true; sortable = $true; facetable = $false },
    @{ name = "metadata_storage_last_modified"; type = "Edm.DateTimeOffset"; searchable = $false; filterable = $true; sortable = $true; facetable = $false },
    @{ name = "metadata_security_id"; type = "Collection(Edm.String)"; searchable = $false; filterable = $true; sortable = $false; facetable = $false },
    @{ name = "chunk_id"; type = "Edm.Int32"; searchable = $false; filterable = $true; sortable = $true; facetable = $false },
    @{ name = "content"; type = "Edm.String"; searchable = $true; filterable = $false; sortable = $false; facetable = $false; analyzer = "standard.lucene" },
    @{ name = "imageCaptions"; type = "Edm.String"; searchable = $true; filterable = $false; sortable = $false; facetable = $false; analyzer = "standard.lucene" },
    @{ name = "page"; type = "Edm.Int32"; searchable = $false; filterable = $true; sortable = $true; facetable = $false },
    @{ name = "offset"; type = "Edm.Int32"; searchable = $false; filterable = $true; sortable = $true; facetable = $false },
    @{ name = "length"; type = "Edm.Int32"; searchable = $false; filterable = $true; sortable = $true; facetable = $false },
    @{ name = "title"; type = "Edm.String"; searchable = $true; filterable = $true; sortable = $false; facetable = $false; analyzer = "standard.lucene" },
    @{ name = "category"; type = "Edm.String"; searchable = $true; filterable = $true; sortable = $false; facetable = $true; analyzer = "standard.lucene" },
    @{ name = "filepath"; type = "Edm.String"; searchable = $true; filterable = $true; sortable = $false; facetable = $false; analyzer = "standard.lucene" },
    @{ name = "url"; type = "Edm.String"; searchable = $false; filterable = $true; sortable = $false; facetable = $false },
    @{ name = "summary"; type = "Edm.String"; searchable = $true; filterable = $false; sortable = $false; facetable = $false; analyzer = "standard.lucene" },
    @{ name = "relatedImages"; type = "Collection(Edm.String)"; searchable = $false; filterable = $false; sortable = $false; facetable = $false },
    @{ name = "relatedFiles"; type = "Collection(Edm.String)"; searchable = $false; filterable = $false; sortable = $false; facetable = $false },
    @{ name = "source"; type = "Edm.String"; searchable = $false; filterable = $true; sortable = $false; facetable = $true },
    @{ name = "contentVector"; type = "Collection(Edm.Single)"; searchable = $true; filterable = $false; sortable = $false; facetable = $false; dimensions = $VectorDimensions; vectorSearchProfile = "myHnswProfile" },
    @{ name = "captionVector"; type = "Collection(Edm.Single)"; searchable = $true; filterable = $false; sortable = $false; facetable = $false; dimensions = $VectorDimensions; vectorSearchProfile = "myHnswProfile" }
  )
  vectorSearch = @{
    profiles = @(
      @{
        name = "myHnswProfile"
        algorithm = "myHnswConfig"
      }
    )
    algorithms = @(
      @{
        name = "myHnswConfig"
        kind = "hnsw"
        hnswParameters = @{
          m = 4
          efConstruction = 400
          efSearch = 500
          metric = "cosine"
        }
      }
    )
  }
  semantic = @{
    configurations = @(
      @{
        name = "my-semantic-config"
        prioritizedFields = @{
          titleField = @{
            fieldName = "title"
          }
          prioritizedContentFields = @(
            @{ fieldName = "content" },
            @{ fieldName = "imageCaptions" },
            @{ fieldName = "summary" }
          )
          prioritizedKeywordsFields = @(
            @{ fieldName = "metadata_storage_name" },
            @{ fieldName = "category" },
            @{ fieldName = "filepath" }
          )
        }
      }
    )
  }
  corsOptions = @{
    allowedOrigins = @("*")
    maxAgeInSeconds = 60
  }
}

$body = $index | ConvertTo-Json -Depth 30 -Compress
$url = "https://$SearchServiceName.search.windows.net/indexes/$IndexName`?api-version=$ApiVersion"
$bodyPath = Join-Path ([System.IO.Path]::GetTempPath()) "$IndexName-search-index.json"
Set-Content -LiteralPath $bodyPath -Value $body -Encoding UTF8

az rest `
  --method put `
  --url $url `
  --headers "Content-Type=application/json" "api-key=$adminKey" `
  --body "@$bodyPath" `
  --output json

if ($LASTEXITCODE -ne 0) {
  throw "Failed to create or update AI Search index $IndexName."
}
