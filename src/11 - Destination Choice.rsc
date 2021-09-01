/*

*/

Macro "Destination Choice" (Args)

    // RunMacro("Split Employment by Earnings", Args)
    // RunMacro("DC Size Terms", Args)
    RunMacro("Calculate Destination Choice", Args)

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
Creates sum product fields using DC size coefficients. Then takes the log
of those fields so it can be fed directly into the DC utility equation.
*/

Macro "DC Size Terms" (Args)

    se_file = Args.SE
    coeff_file = Args.ResDCSizeCoeffs

    se_vw = OpenTable("se", "FFB", {se_file})
    {drive, folder, name, ext} = SplitPath(coeff_file)
    RunMacro("Create Sum Product Fields", {
        view: se_vw, factor_file: coeff_file,
        field_desc: "Resident DC Attractions|See " + name + ext + " for details."
    })

    // Log transform
    coeff_vw = OpenTable("coeff", "CSV", {coeff_file})
    {field_names, } = GetFields(coeff_vw, "All")
    CloseView(coeff_vw)
    // Remove the first and last fields ("Field" and "Description")
    field_names = ExcludeArrayElements(field_names, 1, 1)
    field_names = ExcludeArrayElements(field_names, field_names.length, 1)
    input = GetDataVectors(se_vw + "|", field_names, {OptArray: TRUE})
    for field_name in field_names do
        output.(field_name) = if input.(field_name) + 0
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

    // Determine trip purposes
    trip_types = RunMacro("Get HB Trip Types", Args)
trip_types = {"W_HB_W_All"} // TODO: remove after testing

    opts = null
    opts.primary_spec = {Name: "sov_skim"}
    for trip_type in trip_types do
        if Lower(trip_type) = "w_hb_w_all"
            then segments = {"v0", "ilvi", "ihvi", "ilvs", "ihvs"}
            else segments = {"v0", "vi", "vs"}
        opts.trip_type = trip_type
        opts.zone_utils = input_dc_dir + "/" + Lower(trip_type) + "_zone.csv"
        opts.cluster_utils = input_dc_dir + "/" + Lower(trip_type) + "_cluster.csv"
        opts.cluster_thetas = input_dc_dir + "/" + Lower(trip_type) + "_cluster_thetas.csv"
        
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
                parking: {File: scen_dir + "/output/resident/parking/ParkingLogsums.bin", IDField: "TAZ"}
            }
            opts.cluster_equiv_spec = {File: se_file, ZoneIDField: "TAZ", ClusterIDField: "Cluster"}
            opts.dc_spec = {DestinationsSource: "sov_skim", DestinationsIndex: "Destination"}
            for segment in segments do
                opts.segments = {segment}
                opts.matrices = {
                    sov_skim: {File: sov_skim},
                    mc_logsums: {File: scen_dir + "/output/resident/mode/logsums/" + "logsum_" + trip_type + "_" + segment + "_" + period + ".mtx"}
                }
                opts.output_dir = output_dir
                obj = CreateObject("NestedDC", opts)
                obj.Run()
            end
        end
    end

endmacro