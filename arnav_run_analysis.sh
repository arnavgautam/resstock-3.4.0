#!/bin/bash

states=('ohio') # 'california') # 'florida' 'utah' 'virginia' 'minnesota')# 'montana')
urbanizations=('urban') # 'suburban' 'rural')
for state in "${states[@]}"; do
  for urbanization_level in "${urbanizations[@]}"; do
    # echo "openstudio workflow/run_analysis.rb -y project_${state[0]}/${urbanization_level[0]}_${state[0]}.yml -t all -z ${urbanization_level[0]} -r ${state[0]} -k --num_datapoints 800 -o --baseline"
    openstudio workflow/run_analysis.rb -y project_${state[0]}/${urbanization_level[0]}_${state[0]}.yml -t all -z ${urbanization_level[0]} -r ${state[0]} -k --num_datapoints 800 -o --baseline
    openstudio workflow/run_analysis.rb -y project_${state[0]}/${urbanization_level[0]}_${state[0]}.yml -t all -z ${urbanization_level[0]} -r ${state[0]} -k --num_datapoints 800 -o
  done
done
# openstudio workflow/run_analysis.rb -y project_ohio/urban_ohio.yml -t all -z urban -r ohio -k --num_datapoints 800 -o --baseline