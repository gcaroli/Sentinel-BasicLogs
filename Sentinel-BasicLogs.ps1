$subscriptionId = "7a193200-2bd0-4c88-b579-d8f4ed9a551e"      # Your Azure Subscription ID
$resourceGroup = "mms-ccan"                                   # Resource Group name of your Log Analytics workspace
$workspaceName = "dsbn-oms-ca"                                # Name of your Log Analytics Workspace
$retentionTotal = 90                                          # Your log data retention period in Log Analytics
$archiveRetention = $retentionTotal - 8                       # Basic logs allow for 8 days of logs plus x days for Archive up to the $retentionTotal
$tableName = "Netskope_CL"                                    # Name of the Table to create in Log Analytics
$endpointName = "dce-ns-syslog"                               # Data Collection Endpoint Name
$collectionRuleName = "dcr-custom-ns-syslog"                  # Data Collection Rule Name
$location = "canadaCentral"                                   # Azure Location for your resources
$transformKql = "source"                                      # KQL Code for ingestion time transformation of RawData
$vmResourceGroup = "rg-azurearc-ccan"                         # Resource group name of your Syslog VM in Azure
$vmName = "edcsyslog"                                         # Name of your Syslog VM in Azure
$bVMIsAzureArc = $true                                        # Is your VM in Azure registered in Azure Arc ($true) or a Native Azure VM ($false)
$associationName = ("{0}-association" -f $collectionRuleName) # Name of the DCR to VM Association
$fileName = "//var//log//syslog-custom//ns.log"               # Full path of the custom log file to ingest into Log Analytics.  Note: The '/' MUST be escaped using '//'
 
# Building the ID of the DCE that will be created and the Log Analytics Workspace based on the above parameters.  These will be referenced in the Parameters below
 
$dceId = ("/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Insights/dataCollectionEndpoints/{2}" -f $subscriptionId,$resourceGroup,$endpointName)
$workspaceResourceId = ("/subscriptions/{0}/resourcegroups/{1}/providers/microsoft.operationalinsights/workspaces/{2}" -f $subscriptionId,$resourceGroup,$workspaceName)
 
$tableParams = @"
{
  "properties": {
    "totalRetentionInDays": ${retentionTotal},
    "archiveRetentionInDays": ${archiveRetention},
    "plan": "Basic",
    "schema": {
      "name": "${tableName}",
      "columns": [
      {
        "name": "TimeGenerated",
        "type": "DateTime"
      },
      {
        "name": "RawData",
        "type": "String"
      }
      ]
    }
  }
}
"@
 
$dceParams = @"
{
  "location": "${location}",
  "properties": {
    "networkAcls": {
      "publicNetworkAccess": "Enabled"
    }
  }
}
"@
 
$dcrParams = @"
{
  "location": "${location}",
  "properties": {
    "dataCollectionEndpointId": "${dceId}",
      "streamDeclarations": {
        "Custom-LogFileFormat": {
          "columns": [
          {
            "name": "TimeGenerated",
            "type": "datetime"
          },
          {
            "name": "RawData",
            "type": "string"
          }
          ]
        }
    },
    "dataSources": {
      "logFiles": [
      {
        "streams": [
          "Custom-LogFileFormat" 
        ],
        "filePatterns": [
          "${fileName}"
        ],
        "format": "text",
        "settings": {
          "text": {
            "recordStartTimestampFormat": "ISO 8601"
          }
        },
        "name": "LogFileFormat-Linux"
      }
      ]
    },
    "destinations": {
      "logAnalytics": [
      {
        "workspaceResourceId": "${workspaceResourceId}",
        "name": "${workspaceName}"
      }
      ]
    },
    "dataFlows": [
    {
      "streams": [
        "Custom-LogFileFormat"
      ],
      "destinations": [
        "${workspaceName}"
      ],
      "transformKql": "${transformKql}",
      "outputStream": "Custom-${tableName}"
    }
    ]
  }
}
"@
 
$associationParams = @"
{
  "properties": {
    "dataCollectionRuleId": "/subscriptions/${subscriptionId}/resourceGroups/${resourceGroup}/providers/Microsoft.Insights/dataCollectionRules/${collectionRuleName}"
  }
}
"@
 
Invoke-AzRestMethod -Path ("/subscriptions/{0}/resourcegroups/{1}/providers/microsoft.operationalinsights/workspaces/{2}/tables/{3}?api-version=2021-12-01-preview" -f $subscriptionId,$resourceGroup,$workspaceName,$tableName) -Method PUT -payload $tableParams
Invoke-AzRestMethod -Path ("/subscriptions/{0}/resourcegroups/{1}/providers/Microsoft.Insights/dataCollectionEndpoints/{2}?api-version=2021-04-01" -f $subscriptionId,$resourceGroup,$endpointName) -Method PUT -payload $dceParams
Invoke-AzRestMethod -Path ("/subscriptions/{0}/resourcegroups/{1}/providers/Microsoft.Insights/dataCollectionRules/{2}?api-version=2021-09-01-preview" -f $subscriptionId,$resourceGroup,$collectionRuleName) -Method PUT -payload $dcrParams
if ($bVMIsAzureArc) {
Invoke-AzRestMethod -Path ("/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.HybridCompute/machines/{2}/providers/Microsoft.Insights/dataCollectionRuleAssociations/{3}?api-version=2021-09-01-preview" -f $subscriptionId,$vmResourceGroup,$vmName,$associationName) -Method PUT -payload $associationParams
} else {
Invoke-AzRestMethod -Path ("/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Compute/virtualMachines/{2}/providers/Microsoft.Insights/dataCollectionRuleAssociations/{3}?api-version=2021-09-01-preview" -f $subscriptionId,$vmResourceGroup,$vmName,$associationName) -Method PUT -payload $associationParams
}
