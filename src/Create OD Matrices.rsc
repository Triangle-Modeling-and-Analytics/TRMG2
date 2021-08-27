/*

*/

Macro "Create OD Matrices" (Args)

    RunMacro("Apportion Trips", Args)
    RunMacro("Directionality and Occupancy", Args)

    return(1)
endmacro

/*
With DC and MC probabilities calculated, trip productions can be distributed
into zones and modes.
*/

Macro "Apportion Trips" (Args)

    se_file = Args.SE
    out_dir = Args.[Output Folder]
    dc_dir = out_dir + "/resident/dc"
    mc_dir = out_dir + "/resident/mode"
    periods = Args.periods

    se_vw = OpenTable("se", "FFB", {se_file})

    trip_types = RunMacro("Get HB Trip Types", Args)
// TODO: remove. For testing only
trip_types = {"W_HB_W_All"}
    for period in periods do
        for trip_type in trip_types do
            if Lower(trip_type) = "w_hb_w_all"
                then segments = {"v0", "ilvi", "ilvs", "ihvi", "ihvs"}
                else segments = {"v0", "vi", "vs"}
            
            out_mtx_file = out_dir + "/resident/pa_per_trips_" + trip_type + "_" + period + ".mtx"
            if GetFileInfo(out_mtx_file) <> null then DeleteFile(out_mtx_file)
// TODO: remove. for testing only
segments = {"ihvi"}
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

    return(1)
endmacro

/*
Convert from PA to OD format and from person trips to vehicle trips for the
auto modes.
*/

Macro "Directionality and Occupancy" (Args)

    trip_dir = Args.[Output Folder] + "/resident"
    dir_factor_file = Args.DirectionFactors
    periods = Args.periods

    fac_vw = OpenTable("dir", "CSV", {dir_factor_file})

    trip_types = RunMacro("Get HB Trip Types", Args)
// TODO: remove. For testing only
trip_types = {"W_HB_W_All"}
    for trip_type in trip_types do
        for period in periods do

        end
    end

endmacro