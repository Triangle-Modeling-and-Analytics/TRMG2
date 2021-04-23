/*
After the model is finished, these macros summarize the results into maps
and tables.
*/

Macro "Summaries" (Args)

    RunMacro("Load Link Layer", Args)
    RunMacro("Calculate Daily Fields", Args)
    RunMacro("Create Count Difference Map", Args)
    return(1)
endmacro

/*
This loads the final assignment results onto the link layer.
*/

Macro "Load Link Layer" (Args)

    hwy_dbd = Args.Links
    feedback_iter = Args.FeedbackIteration
    assn_dir = Args.[Output Folder] + "\\assignment\\roadway\\iter_" + String(feedback_iter)
    periods = Args.periods

    {nlyr, llyr} = GetDBLayers(hwy_dbd)

    for period in periods do
        assn_file = assn_dir + "\\roadway_assignment_" + period + ".bin"
        assn_dcb = Substitute(assn_file, ".bin", ".dcb", )

        vw = OpenTable("temp", "FFB", {assn_file})
        {field_names, } = GetFields(vw, "All")
        CloseView(vw)
        RunMacro("Join Table To Layer", hwy_dbd, "ID", assn_file, "ID1")
        {map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd})
        for field_name in field_names do
            if field_name = "ID1" then continue
            RunMacro("Rename Field", llyr, field_name, field_name + "_" + period)
        end

        // Calculate delay by time period and direction
        a_dirs = {"AB", "BA"}
        for dir in a_dirs do

            // Add delay field
            delay_field = dir + "_Delay_" + period
            a_fields = {{
                delay_field, "Real", 10, 2,,,,
                "Hours of Delay|(CongTime - FFTime) * Flow / 60"
            }}
            RunMacro("Add Fields", {view: llyr, a_fields: a_fields})

            // Get data vectors
            v_fft = nz(GetDataVector(llyr + "|", "FFTime", ))
            v_ct = nz(GetDataVector(llyr + "|", dir + "_Time_" + period, ))
            v_vol = nz(GetDataVector(llyr + "|", dir + "_Flow_" + period, ))

            // Calculate delay
            v_delay = (v_ct - v_fft) * v_vol / 60
            v_delay = max(v_delay, 0)
            SetDataVector(llyr + "|", delay_field, v_delay, )
        end

        // LOSD is used for V/C maps. Calculate this.
        for dir in a_dirs do
            field = dir + "_VOC_" + period
            e_field = dir + "_VOCE_" + period
            d_field = dir + "_VOCD_" + period

            // Rename the original field and add a description
            RunMacro("Rename Field", llyr, field, e_field)
            RunMacro("Add Field Description", llyr, e_field, "V/C based on LOS E")

            // Add and calculate the new field (los d)
            a_fields = {{d_field, "Real", 10, 3,,,,"V/C based on LOS D"}}
            RunMacro("Add Fields", {view: llyr, a_fields: a_fields})
            v_flow = GetDataVector(llyr + "|", dir + "_FLOW_PCE_" + period, )
            v_cap = GetDataVector(llyr + "|", dir + period + "CapD", )
            v_vc = v_flow / v_cap
            array.(d_field) = v_vc
        end
        SetDataVectors(llyr + "|", array, )

        CloseMap(map)
    end
endmacro

/*
This macro summarize fields across time period and direction.

The loaded network table will have a volume field for each class that looks like
"AB_Flow_auto_AM". It will also have fields aggregated across classes that look
like "BA_Flow_PM" and "AB_VMT_MD". Direction (AB/BA) and time period (e.g. AM)
will be looped over. Create an array of the rest of the field names to
summarize. e.g. {"Flow_auto", "Flow", "VMT"}.
*/

Macro "Calculate Daily Fields" (Args)

  a_periods = Args.periods
  loaded_dbd = Args.Links
  a_dir = {"AB", "BA"}
  a_classes = {"SOV", "HOV", "SUT", "MUT"}

  // Add link layer to workspace
  {nlyr, llyr} = GetDBLayers(loaded_dbd)
  llyr = AddLayerToWorkspace(llyr, loaded_dbd, llyr)

  // Add "Flow_" to the assignment class name.
  a_fields = V2A("Flow_" + A2V(a_classes))

  // Add other fields to be summed
  a_fields = a_fields + {"Flow", "VMT", "VHT", "Delay"}

  // Calculate additive daily fields
  for f = 1 to a_fields.length do
    field = a_fields[f]

    for d = 1 to a_dir.length do
      dir = a_dir[d]

      field_name = dir + "_" + field + "_Daily"
      a_fields2 = {
        {field_name, "Real", 10, 2,,,,"Daily " + dir + " " + field}
      }
      RunMacro("Add Fields", {view: llyr, a_fields: a_fields2, initial_values: 0})
      v_final = nz(GetDataVector(llyr + "|", field_name, ))

      for p = 1 to a_periods.length do
        period = a_periods[p]

        per_field = dir + "_" + field + "_" + period
        v_add = GetDataVector(llyr + "|", per_field, )
        v_final = v_final + v_add
      end

      // Set field values
      SetDataVector(llyr + "|", field_name, v_final, )
    end
  end

  // Combine AB/BA into total daily flows commonly used to compare to counts.
  // Flow is done separately from VMT, VHT, and Delay because the flow fields
  // are by assignment class. The others are not.
  a_type = a_classes + {""}
  for t = 1 to a_type.length do
    type = a_type[t]

    if type = "" then do
      field_name = "Flow_Daily"
      ab_field = "AB_Flow_Daily"
      ba_field = "BA_Flow_Daily"
    end else do
      field_name = type + "_" + "Flow_Daily"
      ab_field = "AB_Flow_" + type + "_Daily"
      ba_field = "BA_Flow_" + type + "_Daily"
    end
    a_fields = {{
      field_name, "Real", 10, 2,,,,
      "Daily " + type + " flow in both directions"
    }}
    RunMacro("Add Fields", {view: llyr, a_fields: a_fields})

    v_ab = nz(GetDataVector(llyr + "|", ab_field, ))
    v_ba = nz(GetDataVector(llyr + "|", ba_field, ))
    v_tot = v_ab + v_ba

    SetDataVector(llyr + "|", field_name, v_tot, )
  end

  // Combine AB/BA daily fields for VMT, VHT, and Delay
  a_type = {"VMT", "VHT", "Delay"}
  for t = 1 to a_type.length do
    type = a_type[t]

    a_fields = {{
      type + "_Daily", "Real", 10, 2,,,,
      "Daily " + type + " in both directions"
    }}
    RunMacro("Add Fields", {view: llyr, a_fields: a_fields})

    v_ab = nz(GetDataVector(llyr + "|", "AB_" + type + "_Daily", ))
    v_ba = nz(GetDataVector(llyr + "|", "BA_" + type + "_Daily", ))
    v_tot = v_ab + v_ba

    SetDataVector(llyr + "|", type + "_Daily", v_tot, )
  end

  // Calculate non-additive daily fields
  a_fields = {
    {"AB_Speed_Daily", "Real", 10, 2,,,, "Slowest speed throughout day"},
    {"BA_Speed_Daily", "Real", 10, 2,,,, "Slowest speed throughout day"},
    {"AB_Time_Daily", "Real", 10, 2,,,, "Highest time throughout day"},
    {"BA_Time_Daily", "Real", 10, 2,,,, "Highest time throughout day"},
    {"AB_VOCE_Daily", "Real", 10, 2,,,, "Highest LOS E v/c throughout day"},
    {"BA_VOCE_Daily", "Real", 10, 2,,,, "Highest LOS E v/c throughout day"},
    {"AB_VOCD_Daily", "Real", 10, 2,,,, "Highest LOS D v/c throughout day"},
    {"BA_VOCD_Daily", "Real", 10, 2,,,, "Highest LOS D v/c throughout day"}
  }
//   RunMacro("TCB Add View Fields", {llyr, a_fields})
  RunMacro("Add Fields", {view: llyr, a_fields: a_fields})

  for d = 1 to a_dir.length do
    dir = a_dir[d]

    v_min_speed = GetDataVector(llyr + "|", dir + "_Speed_Daily", )
    v_min_speed = if (v_min_speed = null) then 9999 else v_min_speed
    v_max_time = GetDataVector(llyr + "|", dir + "_Time_Daily", )
    v_max_time = if (v_max_time = null) then 0 else v_max_time
    // LOS E v/c
    v_max_voce = nz(GetDataVector(llyr + "|", dir + "_VOCE_Daily", ))
    // LOS D v/c
    v_max_vocd = nz(GetDataVector(llyr + "|", dir + "_VOCD_Daily", ))

    for p = 1 to a_periods.length do
      period = a_periods[p]

      v_speed = GetDataVector(llyr + "|", dir + "_Speed_" + period, )
      v_time = GetDataVector(llyr + "|", dir + "_Time_" + period, )
      v_voce = GetDataVector(llyr + "|", dir + "_VOCE_" + period, )
      v_vocd = GetDataVector(llyr + "|", dir + "_VOCD_" + period, )

      v_min_speed = min(v_min_speed, v_speed)
      v_max_time = max(v_max_time, v_time)
      v_max_voce = max(v_max_voce, v_voce)
      v_max_vocd = max(v_max_vocd, v_vocd)
    end

    SetDataVector(llyr + "|", dir + "_Speed_Daily", v_min_speed, )
    SetDataVector(llyr + "|", dir + "_Time_Daily", v_max_time, )
    SetDataVector(llyr + "|", dir + "_VOCE_Daily", v_max_voce, )
    SetDataVector(llyr + "|", dir + "_VOCD_Daily", v_max_vocd, )
  end
EndMacro

/*

*/

Macro "Create Count Difference Map" (Args)
  
  output_dir = Args.[Output Folder]
  hwy_dbd = Args.Links

  // Create total count diff map
  opts = null
  opts.output_file = output_dir +
    "/_summaries/maps/Count Difference - Total.map"
  opts.hwy_dbd = hwy_dbd
  opts.count_id_field = "CountID"
  opts.count_field = "DailyCount"
  opts.vol_field = "Flow_Daily"
  opts.field_suffix = "All"
  RunMacro("Count Difference Map", opts)

//   // Create SUT count diff map
//   opts = null
//   opts.output_file = output_dir +
//     "/_summaries/maps/Count Difference - SUT.map"
//   opts.hwy_dbd = hwy_dbd
//   opts.count_id_field = "CountID"
//   opts.count_field = "SUTCount"
//   opts.vol_field = "SUT_Flow_Daily"
//   opts.field_suffix = "SUT"
//   RunMacro("Count Difference Map", opts)

//   // Create MUT count diff map
//   opts = null
//   opts.output_file = output_dir +
//     "/_summaries/maps/Count Difference - MUT.map"
//   opts.hwy_dbd = hwy_dbd
//   opts.count_id_field = "CountID"
//   opts.count_field = "MUTCount"
//   opts.vol_field = "MUT_Flow_Daily"
//   opts.field_suffix = "MUT"
//   RunMacro("Count Difference Map", opts)
EndMacro