from os import getcwd
from os.path import join, dirname, exists
import pandas as pd
from scipy.stats import wasserstein_distance
import numpy as np
from scipy.spatial.distance import cdist
import ot
from sklearn.cluster import KMeans
from sklearn.neighbors import KernelDensity
import matplotlib.pyplot as plt
from matplotlib.colors import Normalize
from matplotlib.dates import date2num, DateFormatter, MonthLocator
import json
import pickle
from collections import defaultdict
from itertools import product, cycle
from pprint import pprint
from math import ceil, sqrt
import textwrap
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta
import random
# from matplotlib import colormaps

def get_season(date):
        if date.month in [12, 1, 2]:
                return 'Winter'
        elif date.month in [3, 4, 5]:
                return 'Spring'
        elif date.month in [6, 7, 8]:
                return 'Summer'
        else:
                return 'Fall'

def collect_resstock_data(cityname, num_residences, residence_type="all", casename=None, offset_needed=False, desired_csv_data=None, desired_json_data=None, include_default_data = True, num_of_random_samples = None, residences_to_collect = None):
        resstock_data_dfs = []
        resstock_building_ids = []
        if residences_to_collect is not None:
                pass
        elif num_of_random_samples is not None:
                random.seed(0)
                residences_to_collect = random.sample(range(num_residences), num_of_random_samples)
        else:
                residences_to_collect = range(num_residences)
        for i in residences_to_collect:
                if offset_needed:
                        j = i + 1 + num_residences
                else:
                        j = i + 1
                hvac_electricity_use_cols = ["End Use: Electricity: Heating",
                        "End Use: Electricity: Heating Fans/Pumps",
                        "End Use: Electricity: Heating Heat Pump Backup",
                        "End Use: Electricity: Heating Heat Pump Backup Fans/Pumps",
                        "End Use: Electricity: Cooling",
                        "End Use: Electricity: Cooling Fans/Pumps"]
                desired_cols = ["Time", "Fuel Use: Electricity: Total", "Weather: Drybulb Temperature", "Temperature: Conditioned Space"]
                desired_heating_cols = ["End Use: Electricity: Heating", "End Use: Electricity: Heating Fans/Pumps", "End Use: Electricity: Heating Heat Pump Backup", "End Use: Electricity: Heating Heat Pump Backup Fans/Pumps"]
                desired_cooling_cols = ["End Use: Electricity: Cooling", "End Use: Electricity: Cooling Fans/Pumps"]
                desired_hvac_cols = desired_heating_cols + desired_cooling_cols
                filepath = join(f"{cityname}_{num_residences}_{residence_type}_unit_residence{'' if casename is None else f'_{casename}'}", f'run{j}','run', 'results_timeseries.csv') # "resstock-3.2.0_repo","resstock-3.2.0",
                try:
                        timeseries_data = pd.read_csv(filepath, low_memory=True, header=[0,1])
                except Exception as e:
                        print(f"run {j} at {filepath} couldn't be added")
                        continue
                data_point_out_filepath = join(f"{cityname}_{num_residences}_{residence_type}_unit_residence{'' if casename is None else f'_{casename}'}", f'run{j}','run', 'data_point_out.json') # "resstock-3.2.0_repo","resstock-3.2.0",
                try:
                        with open(data_point_out_filepath, "r") as f:
                                json_data = json.load(f)
                                building_id = json_data["BuildExistingModel"]["building_id"]
                                # TODO:output this if I need it
                                if desired_json_data is not None:
                                        for desired_json_attribute in desired_json_data:
                                                print(json_data["BuildExistingModel"][desired_json_attribute])
                                # else:
                                resstock_building_ids.append(building_id)
                except Exception as e:
                        print(f"run {j} at {data_point_out_filepath} couldn't be added")
                        continue
                timeseries_data.columns = timeseries_data.columns.droplevel(1)
                available_heating_cols = [col for col in desired_heating_cols if col in timeseries_data.columns]
                if len(available_heating_cols) == 0:
                        print("No heating data available")
                available_cooling_cols = [col for col in desired_cooling_cols if col in timeseries_data.columns]
                if len(available_heating_cols) == 0:
                        print("No cooling data available")
                available_hvac_cols = available_heating_cols + available_cooling_cols
                if include_default_data:
                        desired_cols += available_hvac_cols
                if desired_csv_data is not None:
                        desired_cols += [attr_name for attr_name in desired_csv_data if attr_name in timeseries_data.columns and attr_name not in desired_cols]
                timeseries_data = timeseries_data[desired_cols] # Not narrowing down columns when we care about other characteristics of the homes
                if include_default_data:
                
                        for col in available_hvac_cols:
                                timeseries_data[col] = timeseries_data[col].astype(float)
                        timeseries_data["Heating Electricity"] = 0
                        for col in available_heating_cols:
                                if col in timeseries_data.columns:
                                        timeseries_data["Heating Electricity"] += timeseries_data[col]
                        timeseries_data["Cooling Electricity"] = 0
                        for col in available_cooling_cols:
                                if col in timeseries_data.columns:
                                        timeseries_data["Cooling Electricity"] += timeseries_data[col]
                        timeseries_data["HVAC Electricity"] = 0
                        for col in available_hvac_cols:
                                if col in timeseries_data.columns:
                                        timeseries_data["HVAC Electricity"] += timeseries_data[col]
                
                        # Assuming 'Time' column is of datetime type, if not convert it
                        timeseries_data['Time'] = pd.to_datetime(timeseries_data['Time'])
                        timeseries_data['Season'] = timeseries_data['Time'].apply(get_season)
                        timeseries_data['Indoor'] = timeseries_data['Temperature: Conditioned Space']
                        timeseries_data['Outdoor'] = timeseries_data['Weather: Drybulb Temperature']

                resstock_data_dfs.append(timeseries_data)
        return resstock_data_dfs, resstock_building_ids

national_resstock_data_dfs_Baseline, national_resstock_building_ids_Baseline = collect_resstock_data("national_ASHP", 8000, casename=None, include_default_data = False)

national_resstock_data_dfs_ASHP, national_resstock_building_ids_ASHP = collect_resstock_data("national_ASHP", 8000, casename="ASHP", include_default_data = False)

# fig, axes = plt.subplots(1,2,sharey=True, figsize=(10,5))
# primary_attribute = "Weather: Drybulb Temperature"
# secondary_attribute = "Temperature: Conditioned Space"
# hist2d_data_baseline = pd.concat(building_resstock_df[[primary_attribute, secondary_attribute]] for building_resstock_df in national_resstock_data_dfs_Baseline)
# hist2d_data_ASHP = pd.concat(building_resstock_df[[primary_attribute, secondary_attribute]] for building_resstock_df in national_resstock_data_dfs_ASHP)
# axes[0].hist2d(hist2d_data_baseline[primary_attribute], hist2d_data_baseline[secondary_attribute], cmap="Reds", bins=100) #, norm="log")
# axes[1].hist2d(hist2d_data_ASHP[primary_attribute], hist2d_data_ASHP[secondary_attribute], cmap="Reds", bins=100) #, norm="log")
# axes[0].set_xlabel(f"{primary_attribute} (F)")
# axes[1].set_xlabel(f"{primary_attribute} (F)")
# axes[0].set_ylabel(f"{secondary_attribute} (F)")
# axes[1].set_ylabel(f"{secondary_attribute} (F)")
# axes[0].set_title("Baseline")
# axes[1].set_title("Upgrade to ASHP")
# fig.suptitle(f"Heat maps of {secondary_attribute} against {primary_attribute} for baseline and upgrade")

# fig.savefig(join("/ocean", "projects", "eng220005p", "agautam3", "resstock-3.4.0", "temp_heatmaps_national_8000.svg"))


fig, axes = plt.subplots(1,2,sharey=True, figsize=(10,5))
primary_attribute = "Weather: Drybulb Temperature"
secondary_attribute = "Fuel Use: Electricity: Total"
hist2d_data_baseline = pd.concat(building_resstock_df[[primary_attribute, secondary_attribute]] for building_resstock_df in national_resstock_data_dfs_Baseline)
hist2d_data_ASHP = pd.concat(building_resstock_df[[primary_attribute, secondary_attribute]] for building_resstock_df in national_resstock_data_dfs_ASHP)
axes[0].hist2d(hist2d_data_baseline[primary_attribute], hist2d_data_baseline[secondary_attribute], cmap="Reds", bins=100, norm="log")
axes[1].hist2d(hist2d_data_ASHP[primary_attribute], hist2d_data_ASHP[secondary_attribute], cmap="Reds", bins=100, norm="log")
axes[0].set_xlabel(f"{primary_attribute} (F)")
axes[1].set_xlabel(f"{primary_attribute} (F)")
axes[0].set_ylabel(f"{secondary_attribute} (kWh)")
axes[1].set_ylabel(f"{secondary_attribute} (kWh)")
axes[0].set_title("Baseline")
axes[1].set_title("Upgrade to ASHP")
fig.suptitle(f"Heat maps of {secondary_attribute} against {primary_attribute} for baseline and upgrade")

fig.savefig(join("/ocean", "projects", "eng220005p", "agautam3", "resstock-3.4.0", "temp_energy_heatmaps_national_8000.svg"))
