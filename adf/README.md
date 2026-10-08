# Azure Data Factory: schedule the Databricks medallion job

ADF runs the existing Databricks job `medallion_pipeline` (ID `527613356560453`) and waits for it to finish.
The Databricks workspace is on AWS, so ADF's built-in Databricks activities (Azure Databricks only) cannot be
used. The pipeline calls the Databricks **Jobs REST API** with Web activities instead.

```
tr_daily_medallion (06:00 UTC)
  -> pl_run_medallion_databricks
       GetDatabricksToken   read the token from Key Vault (managed identity, output secured)
       RunDatabricksJob     POST /api/2.1/jobs/run-now   {"job_id": ..., "job_parameters": {"batch": ...}}
       WaitForJobToFinish   poll GET /api/2.1/jobs/runs/get until life_cycle_state is terminal (max 3 h)
       CheckJobResult       result_state == SUCCESS ? ok : Fail activity (pipeline shows Failed)
```

## Files
| File | Purpose |
|---|---|
| `pipeline/pl_run_medallion_databricks.json` | the pipeline (parameters: workspace_host, job_id, batch, key_vault_name, secret_name, poll_seconds) |
| `trigger/tr_daily_medallion.json` | daily schedule trigger, created Stopped |

## What you need before deploying
1. Azure subscription, resource group and a **Data Factory (V2)**.
2. An **Azure Key Vault** with a secret `databricks-token`. Use a Databricks personal access token, or an OAuth
   access token from a service principal. Never put the token in the pipeline or in Git.
3. Give the factory's **managed identity** the Key Vault role **Key Vault Secrets User**
   (Key Vault > Access control (IAM) > Add role assignment > select the Data Factory name).
4. The Databricks identity that owns the token must be able to run job `527613356560453`.
5. Replace `<KEY_VAULT_NAME>` in both JSON files.

## Deploy (portal)
1. ADF Studio > **Author** > **Pipelines** > `...` > **New pipeline**, switch to the **{} code** view, paste
   `pl_run_medallion_databricks.json`, then **Publish**.
2. **Manage** > **Triggers** > **New**, or paste `tr_daily_medallion.json` the same way, **Publish**, then
   start the trigger.
3. Test first with **Add trigger > Trigger now** and watch **Monitor > Pipeline runs**.

## Notes
- `batch` is passed to the Databricks job parameter of the same name. Scheduling `batch_1` every day re-reads the
  same folder, which is safe (the load is idempotent) but never picks up new data. For real daily data, point the
  trigger at a dated folder, for example `@formatDateTime(trigger().scheduledTime, 'yyyyMMdd')`, and land files there.
- Never schedule `batch_1` after `batch_2` on this sample data: raw is reloaded from the older snapshot, which
  reverts the SCD-1 tables (departments, orders). SCD-2 tables are protected by their guard.
- This was written against the Databricks Jobs 2.1 API and checked against real Databricks run output. It has not
  been deployed or run in an Azure subscription yet.
