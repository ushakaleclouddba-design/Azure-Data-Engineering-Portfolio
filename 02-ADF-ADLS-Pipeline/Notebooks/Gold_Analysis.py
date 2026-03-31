# Databricks notebook source
# ── Cell 1: Configure ADLS Gen2 access directly ─────────────────────────────
# Uses account key config on Spark context — no mount needed

storage_account = "ushaadfpocadls"
access_key      = ""<ADLS_KEY_REDACTED_USE_KEY_VAULT_IN_PRODUCTION>""

spark.conf.set(
    f"fs.azure.account.key.{storage_account}.dfs.core.windows.net",
    access_key
)

print("ADLS Gen2 access configured")

# COMMAND ----------

# ── Cell 2: List transaction folder ──────────────────────────────────────────
files = dbutils.fs.ls(
    "abfss://curated@ushaadfpocadls.dfs.core.windows.net/transaction/"
)
for f in files:
    print(f.name, f.size)

# COMMAND ----------

# ── Cell 3: Read Gold Parquet into Spark DataFrame ───────────────────────────
df_gold = spark.read.parquet(
    "abfss://curated@ushaadfpocadls.dfs.core.windows.net/transaction/gold_transactions.parquet"
)

print(f"Row count: {df_gold.count()}")
df_gold.printSchema()
display(df_gold)

# COMMAND ----------

# ── Cell 4: Portfolio analytics — transaction mix ────────────────────────────
from pyspark.sql import functions as F

total = df_gold.agg(F.sum("TotalAmount")).collect()[0][0]

summary = df_gold.withColumn(
    "PctOfTotal", F.round((F.col("TotalAmount") / total) * 100, 2)
).withColumn(
    "TotalAmount", F.round(F.col("TotalAmount"), 2)
).withColumn(
    "AvgAmount", F.round(F.col("AvgAmount"), 2)
).orderBy(F.desc("TransactionCount"))

print(f"Total portfolio value: ${total:,.2f}")
display(summary)

# COMMAND ----------

# ── Cell 5: Write Gold DataFrame as Delta table ──────────────────────────────
delta_path = "abfss://curated@ushaadfpocadls.dfs.core.windows.net/transaction/delta_transactions"

df_gold.write \
    .format("delta") \
    .mode("overwrite") \
    .save(delta_path)

print(f"Delta table written to {delta_path}")

df_delta = spark.read.format("delta").load(delta_path)
print(f"Delta row count: {df_delta.count()}")

# COMMAND ----------

# ── Cell 6: Delta MERGE — upsert simulation ──────────────────────────────────
from delta.tables import DeltaTable
from pyspark.sql import functions as F

# Simulate updated records arriving — 2 transaction types with new amounts
updates = spark.createDataFrame([
    ("Interest", 9999999999.00, 999999, 9999.99),
    ("Fee",      1111111111.00, 111111, 9999.99),
], ["TransactionType", "TotalAmount", "TransactionCount", "AvgAmount"])

delta_table = DeltaTable.forPath(spark, delta_path)

delta_table.alias("target").merge(
    updates.alias("source"),
    "target.TransactionType = source.TransactionType"
).whenMatchedUpdateAll() \
 .whenNotMatchedInsertAll() \
 .execute()

print("MERGE complete — updated 2 rows")
display(spark.read.format("delta").load(delta_path).orderBy("TransactionType"))