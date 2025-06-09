#!/bin/bash

zones=('7AK') # 'california') # 'florida' 'utah' 'virginia' 'minnesota')# 'montana')
urbanizations=('suburban') # 'suburban' 'rural')
for zone in "${zones[@]}"; do
  for urbanization_level in "${urbanizations[@]}"; do
    # echo "openstudio workflow/run_analysis.rb -y project_national/${urbanization_level[0]}_${state[0]}.yml -t all -z ${urbanization_level[0]} -r ${state[0]} -k --num_datapoints 800 -o --baseline"
    openstudio workflow/run_analysis.rb -y project_national/national_ASHP.yml -t all -z ${urbanization_level[0]} -r ${zone[0]} -k --num_datapoints 8 -o --baseline
    openstudio workflow/run_analysis.rb -y project_national/national_ASHP.yml -t all -z ${urbanization_level[0]} -r ${zone[0]} -k --num_datapoints 8 -o
  done
done
# openstudio workflow/run_analysis.rb -y project_ohio/urban_ohio.yml -t all -z urban -r ohio -k --num_datapoints 800 -o --baseline