from pyspark.sql import SparkSession
from pyspark.sql.types import *
from pyspark.ml.feature import StringIndexer
from pyspark.ml import Pipeline
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import roc_auc_score, average_precision_score
import numpy as np
import pandas as pd
import pickle
import cdsw
import os
import time

spark = SparkSession.builder \
      .appName("Predictive Maintenance") \
      .getOrCreate()

# read 21 colunms large file from HDFS
schemaData = StructType([StructField("0", DoubleType(), True),
                         StructField("1", DoubleType(), True),
                         StructField("2", DoubleType(), True),
                         StructField("3", DoubleType(), True),
                         StructField("4", DoubleType(), True),
                         StructField("5", DoubleType(), True),
                         StructField("6", DoubleType(), True),     
                         StructField("7", DoubleType(), True),     
                         StructField("8", DoubleType(), True),     
                         StructField("9", DoubleType(), True),     
                         StructField("10", DoubleType(), True),     
                         StructField("11", DoubleType(), True),          
                         StructField("12", IntegerType(), True)])

iot_data = spark.read.schema(schemaData).csv('/user/' 
                                             + os.environ['HADOOP_USER_NAME'] 
                                             + '/historical_iot.txt')


# Create Pipeline
label_indexer = StringIndexer(inputCol = '12', outputCol = 'label')
plan_indexer = StringIndexer(inputCol = '1', outputCol = '1_indexed')
pipeline = Pipeline(stages=[plan_indexer, label_indexer])
indexed_data = pipeline.fit(iot_data).transform(iot_data)
(train_data, test_data) = indexed_data.randomSplit([0.7, 0.3])

pdTrain = train_data.toPandas()
pdTest = test_data.toPandas()

# 12 features
features = ["1_indexed",
            "0", 
            "2", 
            "3",
            "4", 
            "5", 
            "6",
            "7", 
            "8", 
            "9", 
            "10",
            "11"]

param_numTrees = int(sys.argv[1])
param_maxDepth = int(sys.argv[2])
param_impurity = 'gini'

randF=RandomForestClassifier(n_jobs=10,
                             n_estimators=param_numTrees, 
                             max_depth=param_maxDepth, 
                             criterion = param_impurity,
                             random_state=0)

cdsw.track_metric("numTrees",param_numTrees)
cdsw.track_metric("maxDepth",param_maxDepth)
cdsw.track_metric("impurity",param_impurity)

# Fit and Predict
randF.fit(pdTrain[features], pdTrain['label'])
predictions=randF.predict(pdTest[features])

#temp = randF.predict_proba(pdTest[features])

pd.crosstab(pdTest['label'], predictions, rownames=['Actual'], colnames=['Prediction'])

list(zip(pdTrain[features], randF.feature_importances_))


y_true = pdTest['label']
y_scores = predictions
auroc = roc_auc_score(y_true, y_scores)
ap = average_precision_score (y_true, y_scores)
print(auroc, ap)

cdsw.track_metric("auroc", auroc)
cdsw.track_metric("ap", ap)

pickle.dump(randF, open("iot_model.pkl","wb"))

cdsw.track_file("iot_model.pkl")

time.sleep(15)
print("Slept for 15 seconds.")
