#!/bin/bash

# zones=('6B' '7A' '7B' '8AK') # 'utah' 'virginia' 'minnesota')# 'montana')
# urbanizations=('urban' 'suburban')
zones=('6B')
urbanizations=('urban')
for zone in "${zones[@]}"; do
  for urbanization_level in "${urbanizations[@]}"; do
    # echo 'ruby resources/run_sampling.rb -p project_national -n 8 -o national/${zone[0]}_${urbanization_level[0]}_8_all_unit_buildstock.csv --force_values={"ASHRAE IECC Climate Zone 2004":"${zone[0]}","PUMA Metro Status":"${urbanization_level[0]}"}'
    ruby resources/run_sampling.rb -p project_national -n 8 -o national/${zone[0]}_${urbanization_level[0]}_8_all_unit_buildstock.csv --force_values='{"ASHRAE IECC Climate Zone 2004":"'"${zone[0]}"'","PUMA Metro Status":"'"${urbanization_level[0]}"'"}'
  done
done

# ruby resources/run_sampling.rb -p project_national -n 8 -o national/all_national_8_all_unit_buildstock.csv --force_values='{"ASHRAE IECC Climate Zone 2004":"'"${zone[0]}"'","PUMA Metro Status":"'"${urbanization_level[0]}"'"}'