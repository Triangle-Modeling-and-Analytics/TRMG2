/*

*/

Macro "Create OD Matrices" (Args)

    RunMacro("Apportion Resident Trips", Args)
    RunMacro("Directionality", Args)
    RunMacro("Add Airport Trips", Args)
    RunMacro("Collapse Auto Modes", Args)
    RunMacro("Occupancy", Args)

    return(1)
endmacro

/*
With DC and MC probabilities calculated, resident trip productions can be 
distributed into zones and modes.
*/

Macro "Apportion Resident Trips" (Args)

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
// TODO: remove. For testing only
trip_types = {"W_HB_W_All"}
periods = {"AM"}
    for period in periods do

        // Resident trips
        for trip_type in trip_types do
            if Lower(trip_type) = "w_hb_w_all"
                then segments = {"v0", "ilvi", "ilvs", "ihvi", "ihvs"}
                else segments = {"v0", "vi", "vs"}
            
            out_mtx_file = trip_dir + "/pa_per_trips_" + trip_type + "_" + period + ".mtx"
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
Convert from PA to OD format
*/

Macro "Directionality" (Args)

    trip_dir = Args.[Output Folder] + "/resident/trip_tables"
    dir_factor_file = Args.DirectionFactors
    periods = Args.periods

    fac_vw = OpenTable("dir", "CSV", {dir_factor_file})
    rh = GetFirstRecord(fac_vw + "|", )
    auto_modes = {"sov", "hov2", "hov3", "auto_pay", "other_auto"}
    prev_type = ""
    while rh <> null do
        trip_type = fac_vw.trip_type
        period = fac_vw.tod
        pa_factor = fac_vw.pa_fac

// TODO: Remove. for testing only
trip_type = "W_HB_W_All"
period = "AM"
pa_factor = 0.996080828

        pa_mtx_file = trip_dir + "/pa_per_trips_" + trip_type + "_" + period + ".mtx"
        od_mtx_file = trip_dir + "/od_per_trips_" + trip_type + "_" + period + ".mtx"
        if trip_type <> prev_type then CopyFile(pa_mtx_file, od_mtx_file)
        mtx = CreateObject("Matrix", od_mtx_file)
        cores = mtx.GetCores()
        t_mtx = mtx.Transpose({Cores: auto_modes})
        t_cores = t_mtx.GetCores()
        for mode in auto_modes do
            cores.(mode) := cores.(mode) * pa_factor + t_cores.(mode) * (1 - pa_factor)
        end
CloseView(fac_vw)
return()
        prev_type = trip_type
        rh = GetNextRecord(fac_vw + "|", rh, )
    end
    CloseView(fac_vw)
endmacro

/*
The output of the airport model is an OD person matrix of trips by time of day.
This macro adds them to the appropriate resident od trip matrix.
*/

Macro "Add Airport Trips" (Args)
    
    periods = Args.periods
    out_dir = Args.[Output Folder]
    mc_dir = out_dir + "/resident/mode"
    trip_dir = out_dir + "/resident/trip_tables"

    // Which trip type and segment to use for modal probabilities
    trip_type = "N_HB_OD_Long"
    segment = "vs"
// TODO remove after testing
trip_type = "W_HB_W_All"
segment = "ihvs"
    
    air_mtx = CreateObject("Matrix", out_dir + "/airport/Airport_Trips.mtx")
    for period in periods do
        mc_mtx_file = mc_dir + "/probabilities/probability_" + trip_type + "_" + segment + "_" + period + ".mtx"
        mc_mtx = CreateObject("Matrix", mc_mtx_file)
        out_mtx_file = trip_dir + "/od_per_trips_" + trip_type + "_" + period + ".mtx"
        out_mtx = CreateObject("Matrix", out_mtx_file)

        air_core = air_mtx.GetCore("Trips_" + period)
        mode_names = mc_mtx.GetCoreNames()
        out_cores = out_mtx.GetCores()
        for mode in mode_names do
            out_cores.(mode) := nz(out_cores.(mode)) + air_core * mc_cores.(mode)
        end
// TODO remove after testing
return()
    end
endmacro

/*
Collapse auto modes into sov/hov2/hov3
*/

Macro "Collapse Auto Modes" (Args)
    
    trip_dir = Args.[Output Folder] + "/resident/trip_tables"
    shares_file = Args.OtherShares
    periods = Args.periods

    cores_to_collapse = {"auto_pay", "other_auto"}
    fac_vw = OpenTable("shares", "CSV", {shares_file})
    rh = GetFirstRecord(fac_vw + "|", )
    while rh <> null do
        trip_type = fac_vw.trip_type
        sov_fac = fac_vw.sov
        hov2_fac = fac_vw.hov2
        hov3_fac = fac_vw.hov3

//TODO remove after testing
trip_type = "W_HB_W_All"
sov_fac = .33
hov2_fac = .33
hov3_fac = .33

        for period in periods do
            mtx_file = trip_dir + "/od_per_trips_" + trip_type + "_" + period + ".mtx"
            
            mtx = CreateObject("Matrix", mtx_file)
            cores = mtx.GetCores()
            for core_to_collapse in cores_to_collapse do
                cores.sov := cores.sov + cores.(core_to_collapse) * sov_fac
                cores.hov2 := cores.hov2 + cores.(core_to_collapse) * hov2_fac
                cores.hov3 := cores.hov3 + cores.(core_to_collapse) * hov3_fac
            end
            mtx.DropCores({"auto_pay", "other_auto"})
CloseView(fac_vw)
return()
        end
        rh = GetNextRecord(fac_vw + "|", rh, )
    end
    CloseView(fac_vw)
endmacro

/*

*/

Macro "Occupancy" (Args)

    trip_dir = Args.[Output Folder] + "/resident/trip_tables"
    factor_file = Args.HOV3OccFactors
    periods = Args.periods

    fac_vw = OpenTable("factors", "CSV", {factor_file})
    // TODO: this applies only to HB trips currently. When NHB is in place,
    // need to apply it to both.
    SetView(fac_vw)
    SelectByQuery("sel", "several", "Select * where trip_type contains '_HB_'")
    // Loop by period first to reduce the amount of opening/closing matrices
    rh = GetFirstRecord(fac_vw + "|sel", )
    
    prev_trip = ""
    while rh <> null do
        trip_type = fac_vw.trip_type
        period = fac_vw.tod
        hov3_factor = fac_vw.hov3

// TODO: Remove. for testing only
trip_type = "W_HB_W_All"
period = "AM"
hov3_factor = 3.4

        per_mtx_file = trip_dir + "/od_per_trips_" + trip_type + "_" + period + ".mtx"
        veh_mtx_file = trip_dir + "/od_veh_trips_" + trip_type + "_" + period + ".mtx"
        if trip_type <> prev_trip then CopyFile(per_mtx_file, veh_mtx_file)
        mtx = CreateObject("Matrix", veh_mtx_file)
        cores = mtx.GetCores()
        cores.hov2 := cores.hov2 / 2
        cores.hov3 := cores.hov3 / hov3_factor
CloseView(fac_vw)
return()
        prev_trip = trip_type
        rh = GetNextRecord(fac_vw + "|sel", rh, )
    end
    CloseView(fac_vw)
endmacro