# frozen_string_literal: true

# Performs sampling technique and generates CSV file with parameter options for each building.

# The file has to follow general Ruby conventions.
# File name must for the snake case (underscore case) of the class name. For example: WorkerInit = worker_init

require 'csv'
require_relative 'buildstock'
require 'fileutils'
require 'tempfile'

class RunSampling
  def run(project_dir_name, num_samples, outfile, force_values = nil)
    lookup_file = nil
    housing_characteristics_dir = 'housing_characteristics'
    resources_dir = File.absolute_path(File.join(File.dirname(__FILE__), '..', 'resources')) # Should have been uploaded per 'Additional Analysis Files' in PAT
    characteristics_dir = File.absolute_path(File.join(File.dirname(__FILE__), '..', housing_characteristics_dir)) # Should have been uploaded per 'Additional Analysis Files' in PAT
    if not File.exist?(characteristics_dir)
      characteristics_dir = File.absolute_path(File.join(File.dirname(__FILE__), '..', project_dir_name, housing_characteristics_dir)) # Being run locally?
    end

    if lookup_file.nil?
      lookup_file = File.join(resources_dir, 'options_lookup.tsv')
    end

    lookup_csv_data = CSV.open(lookup_file, col_sep: "\t").each.to_a

    params = get_parameters_ordered_from_options_lookup_tsv(lookup_csv_data)

    tsvfiles = {}
    params.each do |param|
      tsvpath = File.join(characteristics_dir, param + '.tsv')
      next if not File.exist?(tsvpath) # Not every parameter used by every mode

      tsvfile = TsvFile.new(tsvpath, nil)
      tsvfiles[param] = tsvfile
    end
    
    if !force_values.nil?
      climate_zone = force_values["ASHRAE IECC Climate Zone 2004"]
      metro_status = force_values["PUMA Metro Status"]
      tsvfiles = get_county_and_puma_tsvfile(project_dir_name, metro_status, tsvfiles)
    end
    
    params = tsvfiles.keys
    if params.size == 0
      register_error('No parameters found, aborting...', nil)
    end

    params = update_parameter_dependencies(params, tsvfiles)
    # puts params
    sample_results = perform_sampling(params, num_samples, tsvfiles, project_dir_name, force_values).transpose
    out_file = write_csv(sample_results, outfile)
    return out_file
  end

  def update_parameter_dependencies(params, tsvfiles)
    # Returns a hash with the dependencies for each parameter
    params_with_deps = {}
    params.each do |param|

      params_with_deps[param] = tsvfiles[param].dependency_cols.keys
    end
    return params_with_deps
  end

  # def build_tsvfile_from_hash(tsv_hash, runner)
  #   tempfile = Tempfile.new(['filtered', '.tsv'])
  
  #   begin
  #     # Write header
  #     tempfile.puts tsv_hash[:header].join("\t")
  
  #     # Write rows
  #     tsv_hash[:rows].each do |row|
  #       tempfile.puts row.join("\t")
  #     end
  
  #     tempfile.flush  # Ensure all content is written to disk
  
  #     # Create a TsvFile from the temp file
  #     TsvFile.new(tempfile.path, runner)
  
  #   ensure
  #     # Keep tempfile open as long as needed; you may delete it later if desired
  #     tempfile.close
  #   end
  # end

  # require 'tempfile'

  def filter_county_puma_by_zone_and_status(climate_zone, metro_status, puma_metro_status_tsvfile, puma_tsvfile, county_puma_tsvfile)
    # Map metro_status to correct column index in puma_metro_status_tsvfile
    status_col_index = case metro_status.downcase
                      when 'urban' then 1
                      when 'suburban' then 2
                      when 'rural' then 3
                      else raise ArgumentError, "Invalid metro status: #{metro_status}"
                      end

    # Step 1: Find relevant PUMA codes from puma_metro_status_tsvfile
    relevant_pumas = puma_metro_status_tsvfile.rows
      .reject { |row| row[0].start_with?('#') }
      .select { |row| row[status_col_index] == '1' }
      .map { |row| row[0].strip }

    # Step 2: From puma_tsvfile, find County+PUMA rows that are assigned to those PUMAs
    # Match if Option=<PUMA> column exists and row has value 1
    matching_county_pumas = puma_tsvfile.rows
      .select do |row|
        relevant_pumas.any? do |puma|
          col_index = puma_tsvfile.option_cols[puma]
          col_index && row[col_index] == '1'
        end
      end
      .map { |row| row[0].strip } # This gives County and PUMA

    # Step 3: From county_puma_tsvfile, filter only the columns named Option=<County and PUMA> where the County and PUMA is one of those matched
    relevant_option_columns = county_puma_tsvfile.header.select do |col|
      col.start_with?('Option=') && matching_county_pumas.include?(col.split('=').last.strip)
    end

    # Step 4: Reconstruct filtered TSV data
    new_header = ['County and PUMA'] + relevant_option_columns

    filtered_rows = county_puma_tsvfile.rows.map do |row|
      [row[0].strip] + relevant_option_columns.map do |col|
        idx = county_puma_tsvfile.header.index(col)
        row[idx]
      end
    end

    # Step 5: Create a new TsvFile object from this filtered data
    build_tsvfile_from_hash({ header: new_header, rows: filtered_rows }, nil)
  end

  def build_tsvfile_from_hash(tsv_hash, runner)
    tempfile = Tempfile.new(['filtered', '.tsv'])

    begin
      # Write header
      tempfile.puts tsv_hash[:header].join("\t")
      # Write data rows
      tsv_hash[:rows].each { |row| tempfile.puts row.join("\t") }

      tempfile.flush
      TsvFile.new(tempfile.path, runner)
    ensure
      tempfile.close
      # Optional: tempfile.unlink  # if you want to delete it right away
    end
  end

  def get_county_and_puma_tsvfile(project_dir_name, metro_status, tsvfiles)
    filtered_county_and_PUMA = File.absolute_path(File.join(File.dirname(__FILE__), '..', project_dir_name, "housing_characteristics", "County and PUMA #{metro_status}.tsv"))
    filtered_PUMA_metro_status = File.absolute_path(File.join(File.dirname(__FILE__), '..', project_dir_name, "housing_characteristics", "PUMA Metro Status #{metro_status}.tsv"))
    filtered_PUMA = File.absolute_path(File.join(File.dirname(__FILE__), '..', project_dir_name, "housing_characteristics", "PUMA #{metro_status}.tsv"))
    tsvfiles["PUMA Metro Status"] = TsvFile.new(filtered_PUMA_metro_status, nil)
    if File.exist?(filtered_county_and_PUMA) and File.exist?(filtered_PUMA_metro_status) and File.exist?(filtered_PUMA)
      puts "Replacing values in tsvfiles from the previously saved values for #{metro_status}"
      tsvfiles["County and PUMA"] = TsvFile.new(filtered_county_and_PUMA, nil)
      tsvfiles["PUMA Metro Status"] = TsvFile.new(filtered_PUMA_metro_status, nil)
      tsvfiles["PUMA"] = TsvFile.new(filtered_PUMA, nil)
    else
      puts "Replacing values in tsvfiles with newly generated values"
      puma_metro_status_tsvfile = tsvfiles["PUMA Metro Status"]
      puma_tsvfile = tsvfiles["PUMA"]
      county_puma_tsvfile = tsvfiles["County and PUMA"]
      
      # tsvfile = filter_county_puma_by_zone_and_status(climate_zone, metro_status, puma_metro_status_tsvfile, puma_tsvfile, county_puma_tsvfile)
      
      # Determine column index based on metro_status
      status_column_index = case metro_status.downcase
      when 'urban' then 1
      when 'suburban' then 2
      when 'rural' then 3
      else
        raise ArgumentError, "Invalid metro status: #{metro_status}"
      end

      # Step 1: Get relevant PUMAs from the metro status file
      pumas_matching_status = puma_metro_status_tsvfile.rows
      .reject { |row| row[0].start_with?('#') }  # skip header or comment lines
      .select { |row| row[status_column_index] == '1' }
      .map { |row| row[0] }  # PUMA is in column 0

      puts "Got PUMAs matching metro status"

      # Step 2: Find matching rows in the PUMA TSV
      option_columns = puma_tsvfile.header.select { |col| col.start_with?("Option=") && pumas_matching_status.include?(col.split('=').last) }

      puts "Got columns of PUMA tsvfile that I need to use to get County and PUMAs"

      county_puma_keys = puma_tsvfile.rows
      .reject { |row| row[0].start_with?('#') }
      .select do |row|
      option_columns.any? { |col| row[puma_tsvfile.header.index(col)] == '1' }
      end
      .map { |row| row[0] }  # "County and PUMA"

      puts "Got the County and PUMAs for the PUMAs of this metro status"

      if not File.exist?(filtered_PUMA)
        filtered_header = ['Dependency=County and PUMA'] + option_columns
        filtered_rows = puma_tsvfile.rows
        .reject { |row| row[0].start_with?('#') }
        .select do |row|
        option_columns.any? { |col| row[puma_tsvfile.header.index(col)] == '1' }
        end

        result =  {
          header: filtered_header,
          rows: filtered_rows
        }
    
        # puts result
    
        File.open(filtered_PUMA, "w") do |file|
          file.puts filtered_header.join("\t")
          filtered_rows.each do |row|
            file.puts row.join("\t")
          end
        end

        tsvfiles["PUMA"] = TsvFile.new(filtered_PUMA, nil)
      end

      # Step 3: Filter County and PUMA TSV to keep only matching Option columns
      relevant_option_columns = county_puma_tsvfile.header.select do |col|
      col.start_with?("Option=") && county_puma_keys.include?(col.split('=').last)
      end

      puts "Got columns of County and PUMAs that I need to keep in the TSV file"

      # Filtered version of the TSV
      filtered_header = ['Dependency=ASHRAE IECC Climate Zone 2004'] + relevant_option_columns
      filtered_rows = county_puma_tsvfile.rows
      .reject { |row| row[0].start_with?('#') }
      .map do |row|
      [row[0]] + relevant_option_columns.map { |col| row[county_puma_tsvfile.header.index(col)] }
      end

      puts "Got the filtered header and the filtered rows"

      # puts filtered_header

      # puts 

      result =  {
        header: filtered_header,
        rows: filtered_rows
      }

      # puts result

      File.open(filtered_county_and_PUMA, "w") do |file|
        file.puts filtered_header.join("\t")
        filtered_rows.each do |row|
          file.puts row.join("\t")
        end
      end

      # end

      tsvfiles["County and PUMA"] = TsvFile.new(filtered_county_and_PUMA, nil)
    
    end

    tsvfiles
  end

  def perform_sampling(params, num_samples, tsvfiles, project_dir_name, force_values)
    results_data = []
    results_data_cols = {}

    # Add building numbers
    results_data_bldgs = ['Building'] + Array(1..num_samples)
    results_data << results_data_bldgs
    results_data_cols[results_data_bldgs[0]] = results_data.size - 1

    random_seed = 57 # Using a hard-coded seed so that we get repeatable results

    # puts params

    processed_params = []
    bldgs_hash = {}
    while processed_params.size != params.size
      params.each do |param, param_deps|
        # Already processed? Skip
        next if processed_params.include?(param)

        # Dependencies not yet processed? Skip until a subsequent pass
        skip = false
        param_deps.each do |param_dep|
          next if processed_params.include?(param_dep)

          skip = true
        end
        next if skip

        puts "Sampling #{project_dir_name}/#{param}..."

        results_data_param = [param] + [nil] * num_samples
        tsvfile = tsvfiles[param]

        # Force a particular value for the parameter if possible
        if !force_values.nil? and force_values.key?(param)
          # puts "Forcing a value"
          forced_value = force_values[param]
        else
          # puts "Not forcing a value"
          forced_value = nil
        end

        # # narrow down the tsvfile for the County and PUMA param
        # if param=="County and PUMA"
        #   # climate_zone = force_values["ASHRAE IECC Climate Zone 2004"]
        #   metro_status = force_values["PUMA Metro Status"]
        #   filtered_county_and_PUMA = File.absolute_path(File.join(File.dirname(__FILE__), '..', project_dir_name, "housing_characteristics", "County and PUMA #{metro_status}.tsv"))
        #   if not File.exist?(filtered_county_and_PUMA)
            
      
        #     puma_metro_status_tsvfile = tsvfiles["PUMA Metro Status"]
        #     puma_tsvfile = tsvfiles["PUMA"]
        #     county_puma_tsvfile = tsvfiles["County and PUMA"]
            
        #     # tsvfile = filter_county_puma_by_zone_and_status(climate_zone, metro_status, puma_metro_status_tsvfile, puma_tsvfile, county_puma_tsvfile)
            
        #     # Determine column index based on metro_status
        #     status_column_index = case metro_status.downcase
        #     when 'urban' then 1
        #     when 'suburban' then 2
        #     when 'rural' then 3
        #     else
        #       raise ArgumentError, "Invalid metro status: #{metro_status}"
        #     end

        #     # Step 1: Get relevant PUMAs from the metro status file
        #     pumas_matching_status = puma_metro_status_tsvfile.rows
        #     .reject { |row| row[0].start_with?('#') }  # skip header or comment lines
        #     .select { |row| row[status_column_index] == '1' }
        #     .map { |row| row[0] }  # PUMA is in column 0

        #     puts "Got PUMAs matching metro status"

        #     # Step 2: Find matching rows in the PUMA TSV
        #     option_columns = puma_tsvfile.header.select { |col| col.start_with?("Option=") && pumas_matching_status.include?(col.split('=').last) }

        #     puts "Got columns of PUMA tsvfile that I need to use to get County and PUMAs"

        #     county_puma_keys = puma_tsvfile.rows
        #     .reject { |row| row[0].start_with?('#') }
        #     .select do |row|
        #     option_columns.any? { |col| row[puma_tsvfile.header.index(col)] == '1' }
        #     end
        #     .map { |row| row[0] }  # "County and PUMA"

        #     puts "Got the County and PUMAs for the PUMAs of this metro status"

        #     # Step 3: Filter County and PUMA TSV to keep only matching Option columns
        #     relevant_option_columns = county_puma_tsvfile.header.select do |col|
        #     col.start_with?("Option=") && county_puma_keys.include?(col.split('=').last)
        #     end

        #     puts "Got columns of County and PUMAs that I need to keep in the TSV file"

        #     # Filtered version of the TSV
        #     filtered_header = ['Dependency=ASHRAE IECC Climate Zone 2004'] + relevant_option_columns
        #     filtered_rows = county_puma_tsvfile.rows
        #     .reject { |row| row[0].start_with?('#') }
        #     .map do |row|
        #     [row[0]] + relevant_option_columns.map { |col| row[county_puma_tsvfile.header.index(col)] }
        #     end

        #     puts "Got the filtered header and the filtered rows"

        #     # puts filtered_header

        #     # puts 

        #     result =  {
        #       header: filtered_header,
        #       rows: filtered_rows
        #     }

        #     # puts result

        #     File.open(filtered_county_and_PUMA, "w") do |file|
        #       file.puts filtered_header.join("\t")
        #       filtered_rows.each do |row|
        #         file.puts row.join("\t")
        #       end
        #     end

        #   end

        #   tsvfile = TsvFile.new(filtered_county_and_PUMA, nil)

        #   # puts tsvfile



        #   # tsvfile = build_tsvfile_from_hash(result, nil) 

        # end

        if param_deps.size == 0
          # No dependencies, perform 'global' sampling
          sample_results = sample_probability_distribution(nil, tsvfile, num_samples, forced_value)
          random_seed = distribute_samples(random_seed, results_data_param, sample_results, Array(1..num_samples))
        else
          # For each combination of dependency values, perform sampling
          dep_hashes = get_combination_hashes(tsvfiles, param_deps)
          # puts dep_hashes
          bldgs_processed = 0
          if not bldgs_hash.keys.include?(param_deps)
            bldgs_hash[param_deps] = get_bldgs_by_dependency_values(results_data, dep_hashes, results_data_cols)
          end
          # puts bldgs_hash
          dep_hashes.each do |dep_hash|
            # Determine buildings this combo applies to
            bldgs = bldgs_hash[param_deps][dep_hash.values]
            # puts bldgs
            next if bldgs.nil?
            puts "Generating values of #{param} for buildings #{bldgs} now"
            # puts dep_hash
            # puts bldgs_hash
            # puts param_deps
            # puts dep_hash.values
            
            sample_results = sample_probability_distribution(dep_hash, tsvfile, bldgs.size, forced_value)
            random_seed = distribute_samples(random_seed, results_data_param, sample_results, bldgs)
            bldgs_processed += bldgs.size
          end
          # Ensure correct number of buildings were processed
          if bldgs_processed != num_samples
            puts bldgs_processed
            register_error('Sampling algorithm unexpectedly failed, not producing enough buildings.', nil)
          end
        end

        # Ensure no missing values
        if results_data_param.include?(nil)
          register_error('Sampling algorithm unexpectedly failed.', nil)
        end

        # Add results for this parameter
        results_data << results_data_param
        results_data_cols[results_data_param[0]] = results_data.size - 1
        processed_params << param

        # We just processed a parameter; start back at the beginning to try
        # to keep the parameters better ordered.
        break
      end
    end

    return results_data
  end

  def get_bldgs_by_dependency_values(results_data, dep_hashes, results_data_cols)
    # Returns a hash with key:dep_hash, value:Array[bldgs]

    data = []
    dep_hashes[0].keys.each do |dep_name|
      data << results_data[results_data_cols[dep_name]]
    end
    data = data.transpose

    bldgs_hash = {}
    data[1..-1].each_with_index do |bldg, idx|
      bldgs_hash[bldg] = [] if bldgs_hash[bldg].nil?
      bldgs_hash[bldg] << idx + 1
    end

    return bldgs_hash
  end

  def get_tsvrow_with_dependency_values(tsvfile, dep_hash)
    # Returns the row of data in the tsvfile with the given dependency values.
    if dep_hash.nil?
      return tsvfile.rows[0]
    end

    rownum = tsvfile.rows_keys_s[dep_hash]

    if rownum.nil?
      register_error("Could not find row in #{tsvfile.filename} with dependency values: #{dep_hash}.", nil)
    end

    return tsvfile.rows[rownum]
  end

  def binary_search(arr, value)
    # Implementation of binary search
    if arr.nil? || arr.size == 0
      return 0
    end

    lo = 0
    hi = arr.size - 1
    m = 0
    while lo < hi
      m = (hi + lo) / 2
      if arr[m] > value
        lo = m + 1
      else
        hi = m - 1
      end
    end
    if arr[lo] > value
      lo += 1
    end
    return lo
  end

  def sample_probability_distribution(dep_hash, tsvfile, num_samples, forced_value)
    # Returns a dictionary with key:option_name, value:num_samples.

    # Create prob_dist hash needed by _sample_probability_distribution method.
    tsvrow = get_tsvrow_with_dependency_values(tsvfile, dep_hash)
    puts tsvrow
    prob_dist = []
    any_nonzero=false
    # puts tsvfile.option_cols
    tsvfile.option_cols.each do |option_name, option_col|
      prob_val = tsvrow[option_col].to_f
      next if prob_val <= 0
      any_nonzero = true
      prob_dist << [option_name, prob_val]
    end
    # any_nonzero and puts "At least something is nonzero"
    !any_nonzero and register_error("Nothing was nonzero", nil)
    puts prob_dist

    return _sample_probability_distribution(prob_dist, num_samples, forced_value)
  end

  def _sample_probability_distribution(prob_dist, num_samples, forced_value)
    # Instead of using Monte Carlo, which for small sample sizes can randomly choose
    # a low probability item, we use a quota sampling algorithm to more strategically
    # (non-randomly) choose the number of samples for each item in order to best
    # represent the input distribution.
    # prob_dist - array of arrays where the inner arrays are of the
    #             form [option_name, probability]
    # num_samples - integer for the total number of samples
    # Returns a dictionary with key:option_name, value:num_samples.

    # puts prob_dist
    # puts num_samples
    # puts forced_value

    if prob_dist.size == 1
      return { prob_dist[0][0] => num_samples } # Simply return num_samples for only item
    end

    if !forced_value.nil?
      puts "Thinking I need to force a value"
      puts forced_value
      return { forced_value => num_samples }
    end

    return_samples = {}
    prob_dist.each do |item|
      return_samples[item[0]] = 0
    end

    # Sort array in descending order
    # Using stable sort algorithm from https://groups.google.com/g/comp.lang.ruby/c/JcDGbaFHifI/m/2gKpc9FQbCoJ
    n = 0
    prob_dist = prob_dist.sort_by { |x| n += 1; [x[1], n] }.reverse

    if num_samples == 1
      return { prob_dist[0][0] => 1 } # Simply return 1 sample for max item
    end

    # We'll never choose to sample an item beyond the first
    # num_samples number of items, so discard the rest.
    if prob_dist.size > num_samples
      prob_dist.slice!(num_samples..prob_dist.size - 1)
    end

    sum = prob_dist.transpose[1].inject(0, :+)
    remaining_samples = num_samples
    while remaining_samples > 0
      # Choose highest probability item (first in array)
      max_item = prob_dist[0]

      # Increment the number of samples for the highest probability
      return_samples[max_item[0]] += 1

      # Calculate new probability
      target_num_samples = remaining_samples * max_item[1] / sum
      new_probability = (target_num_samples - 1) / target_num_samples * max_item[1]

      # Remove item, insert back into the appropriate sorted
      # position based on its new probability value
      prob_dist.delete_at(0)
      index = binary_search(prob_dist.transpose[1], new_probability)
      prob_dist.insert(index, [max_item[0], new_probability])

      # Update sum and remaining_samples
      sum += (new_probability - max_item[1])
      remaining_samples -= 1

      # We'll never choose to sample an item beyond the first
      # remaining_samples number of items, so discard the rest.
      if prob_dist.size > remaining_samples
        prob_dist.pop
      end
    end

    # Remove items with no samples
    return_samples.delete_if { |_k, v| v == 0 }

    if return_samples.values.reduce(:+) != num_samples
      register_error('Sampling algorithm unexpectedly failed.', nil)
    end

    return return_samples
  end

  def distribute_samples(random_seed, results_data_param, sample_results, bldgs)
    # Randomly distributes sample_results to the specified bldgs.
    # Returns an updated results_data_param array.
    bldgs.shuffle(random: Random.new(random_seed)).each do |bldg|
      sample_results.each do |option_name, option_num_samples|
        next if option_num_samples <= 0

        results_data_param[bldg] = option_name
        sample_results[option_name] -= 1 # one less sample to distribute
        break
      end
    end
    return random_seed + 1
  end

  def write_csv(sample_results, outfile)
    # Writes the csv output file.
    out_file = File.absolute_path(File.join(File.dirname(__FILE__), outfile))
    FileUtils.mkdir_p(File.dirname(out_file))
    CSV.open(out_file, 'w') do |csv_object|
      sample_results.each do |sample_result|
        csv_object << sample_result
      end
    end
    puts "Wrote output file #{File.basename(out_file)}."
    return out_file
  end
end
