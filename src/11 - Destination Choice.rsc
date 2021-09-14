/*

*/

Macro "Destination Choice" (Args)

    RunMacro("Split Employment by Earnings", Args)
    RunMacro("DC Attractions", Args)
    RunMacro("DC Size Terms", Args)
    RunMacro("Calculate Destination Choice", Args)
    RunMacro("Apportion Resident HB Trips", Args)

    return(1)
endmacro

/*
The resident DC model needs the low-earning fields for the attraction models.
For work trips, this helps send low income households to low earning jobs.
*/

Macro "Split Employment by Earnings" (Args)

    se_file = Args.SE
    se_vw = OpenTable("se", "FFB", {se_file})
    a_fields = {
        {"Industry_EL", "Real", 10, 2, , , , "Low paying industry jobs"},
        {"Industry_EH", "Real", 10, 2, , , , "High paying industry jobs"},
        {"Office_EL", "Real", 10, 2, , , , "Low paying office jobs"},
        {"Office_EH", "Real", 10, 2, , , , "High paying office jobs"},
        {"Retail_EL", "Real", 10, 2, , , , "Low paying retail jobs"},
        {"Retail_EH", "Real", 10, 2, , , , "High paying retail jobs"},
        {"Service_RateLow_EL", "Real", 10, 2, , , , "Low paying service_rl jobs"},
        {"Service_RateLow_EH", "Real", 10, 2, , , , "High paying service_rl jobs"},
        {"Service_RateHigh_EL", "Real", 10, 2, , , , "Low paying service_rh jobs"},
        {"Service_RateHigh_EH", "Real", 10, 2, , , , "High paying service_rh jobs"}
    }
    RunMacro("Add Fields", {view: se_vw, a_fields: a_fields})

    input = GetDataVectors(
        se_vw + "|",
        {"Industry", "Office", "Retail", "Service_RateLow", "Service_RateHigh", "PctHighPay"},
        {OptArray: "true"}
    )
    output.Industry_EH = input.Industry * input.PctHighPay/100
    output.Industry_EL = input.Industry * (1 - input.PctHighPay/100)
    output.Office_EH = input.Office * input.PctHighPay/100
    output.Office_EL = input.Office * (1 - input.PctHighPay/100)
    output.Retail_EH = input.Retail * input.PctHighPay/100
    output.Retail_EL = input.Retail * (1 - input.PctHighPay/100)
    output.Service_RateLow_EH = input.Service_RateLow * input.PctHighPay/100
    output.Service_RateLow_EL = input.Service_RateLow * (1 - input.PctHighPay/100)
    output.Service_RateHigh_EH = input.Service_RateHigh * input.PctHighPay/100
    output.Service_RateHigh_EL = input.Service_RateHigh * (1 - input.PctHighPay/100)
    SetDataVectors(se_vw + "|", output, )
endmacro

/*
Calculates attractions for the HB work trip type. These attractions are used
as targets for double constraint in the DC.
*/

Macro "DC Attractions" (Args)

    se_file = Args.SE
    rate_file = Args.ResDCAttrRates

    se_vw = OpenTable("se", "FFB", {se_file})
    {drive, folder, name, ext} = SplitPath(rate_file)
    RunMacro("Create Sum Product Fields", {
        view: se_vw, factor_file: rate_file,
        field_desc: "Resident DC Attractions|Used for double constraint.|See " + name + ext + " for details."
    })

    CloseView(se_vw)
endmacro

/*
Creates sum product fields using DC size coefficients. Then takes the log
of those fields so it can be fed directly into the DC utility equation.
*/

Macro "DC Size Terms" (Args)

    se_file = Args.SE
    coeff_file = Args.ResDCSizeCoeffs

    // Before calculating the size term fields, create any additional fields
    // needed for that calculation.
    se_vw = OpenTable("se", "FFB", {se_file})
    a_fields =  {{
        "Hosp_Service", "Real", 10, 2,,,, 
        "Hospital * Total Service Employment.|Used in OMED dc model"
    }}
    RunMacro("Add Fields", {view: se_vw, a_fields: a_fields})
    input = GetDataVectors(
        se_vw + "|",
        {"Hospital", "Service_RateLow", "Service_RateHigh"},
        {OptArray: "true"}
    )
    output.Hosp_Service = input.Hospital * (input.Service_RateLow + input.Service_RateHigh)
    SetDataVectors(se_vw + "|", output, )

    // Calculate the size term fields using the coefficient file
    {drive, folder, name, ext} = SplitPath(coeff_file)
    RunMacro("Create Sum Product Fields", {
        view: se_vw, factor_file: coeff_file,
        field_desc: "Resident DC Size Terms|" +
        "These are already log transformed and used directly by the DC model.|" +
        "See " + name + ext + " for details."
    })

    // Log transform the results and set any 0s to nulls
    coeff_vw = OpenTable("coeff", "CSV", {coeff_file})
    {field_names, } = GetFields(coeff_vw, "All")
    CloseView(coeff_vw)
    // Remove the first and last fields ("Field" and "Description")
    field_names = ExcludeArrayElements(field_names, 1, 1)
    field_names = ExcludeArrayElements(field_names, field_names.length, 1)
    input = GetDataVectors(se_vw + "|", field_names, {OptArray: TRUE})
    for field_name in field_names do
        output.(field_name) = if input.(field_name) = 0
            then null
            else Log(1 + input.(field_name))
    end
    SetDataVectors(se_vw + "|", output, )
    CloseView(se_vw)
endmacro

/*

*/

Macro "Calculate Destination Choice" (Args)

    scen_dir = Args.[Scenario Folder]
    skims_dir = scen_dir + "\\output\\skims\\"
    input_dir = Args.[Input Folder]
    input_dc_dir = input_dir + "/resident/dc"
    output_dir = Args.[Output Folder] + "/resident/dc"
    periods = Args.periods
    sp_file = Args.ShadowPrices

    // Determine trip purposes
    trip_types = RunMacro("Get HB Trip Types", Args)

    opts = null
    opts.output_dir = output_dir
    opts.primary_spec = {Name: "sov_skim"}
    for trip_type in trip_types do
        if Lower(trip_type) = "w_hb_w_all"
            then segments = {"v0", "ilvi", "ihvi", "ilvs", "ihvs"}
            else segments = {"v0", "vi", "vs"}
        opts.trip_type = trip_type
        opts.zone_utils = input_dc_dir + "/" + Lower(trip_type) + "_zone.csv"
        opts.cluster_data = input_dc_dir + "/" + Lower(trip_type) + "_cluster.csv"
        
        if GetFileInfo(nest_file) <> null then opts.nest_file = nest_file

        for period in periods do
            opts.period = period
            
            // Determine which sov skim to use
            if period = "MD" or period = "NT" then do
                tour_type = "All"
                homebased = "All"
            end else do
                tour_type = Upper(Left(trip_type, 1))
                homebased = "HB"
            end
            sov_skim = skims_dir + "roadway/avg_skim_" + period + "_" + tour_type + "_" + homebased + "_sov.mtx"
            
            // Set sources
            se_file = scen_dir + "/output/sedata/scenario_se.bin"
            opts.tables = {
                se: {File: se_file, IDField: "TAZ"},
                parking: {File: scen_dir + "/output/resident/parking/ParkingLogsums.bin", IDField: "TAZ"},
                sp: {File: sp_file, IDField: "TAZ"}
            }
            opts.cluster_equiv_spec = {File: se_file, ZoneIDField: "TAZ", ClusterIDField: "Cluster"}
            opts.dc_spec = {DestinationsSource: "sov_skim", DestinationsIndex: "Destination"}
            for segment in segments do
                opts.segments = {segment}
                opts.matrices = {
                    sov_skim: {File: sov_skim},
                    mc_logsums: {File: scen_dir + "/output/resident/mode/logsums/" + "logsum_" + trip_type + "_" + segment + "_" + period + ".mtx"}
                }
                obj = CreateObject("NestedDC", opts)
                obj.Run()
            end
        end
    end
endmacro

/*
With DC and MC probabilities calculated, resident trip productions can be 
distributed into zones and modes.
*/

Macro "Apportion Resident HB Trips" (Args)

    se_file = Args.SE
    out_dir = Args.[Output Folder]
    dc_dir = out_dir + "/resident/dc"
    mc_dir = out_dir + "/resident/mode"
    trip_dir = out_dir + "/resident/trip_tables"
    periods = Args.periods

    se_vw = OpenTable("se", "FFB", {se_file})

    // Create a folder to hold the trip matrices
    RunMacro("Create Directory", trip_dir)

    trip_types = RunMacro("Get HB Trip Types", Args)

    for period in periods do

        // Resident trips
        for trip_type in trip_types do
            if Lower(trip_type) = "w_hb_w_all"
                then segments = {"v0", "ilvi", "ilvs", "ihvi", "ihvs"}
                else segments = {"v0", "vi", "vs"}
            
            out_mtx_file = trip_dir + "/pa_per_trips_" + trip_type + "_" + period + ".mtx"
            if GetFileInfo(out_mtx_file) <> null then DeleteFile(out_mtx_file)

            for segment in segments do
                name = trip_type + "_" + segment + "_" + period
                
                dc_mtx_file = dc_dir + "/probabilities/probability_" + name + "_zone.mtx"
                dc_mtx = CreateObject("Matrix", dc_mtx_file)
                dc_cores = dc_mtx.GetCores()
                mc_mtx_file = mc_dir + "/probabilities/probability_" + name + ".mtx"
                if segment = segments[1] then do
                    CopyFile(mc_mtx_file, out_mtx_file)
                    out_mtx = CreateObject("Matrix", out_mtx_file)
                    cores = out_mtx.GetCores()
                    core_names = out_mtx.GetCoreNames()
                    for core_name in core_names do
                        cores.(core_name) := nz(cores.(core_name)) * 0
                    end
                end
                mc_mtx = CreateObject("Matrix", mc_mtx_file)
                mc_cores = mc_mtx.GetCores()

                v_prods = nz(GetDataVector(se_vw + "|", name, ))
                v_prods.rowbased = "false"

                mode_names = mc_mtx.GetCoreNames()
                out_cores = out_mtx.GetCores()
                for mode in mode_names do
                    out_cores.(mode) := nz(out_cores.(mode)) + v_prods * dc_cores.final_prob * mc_cores.(mode)
                end
            end
        end
    end
endmacro