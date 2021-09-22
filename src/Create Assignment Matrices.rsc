/*

*/

Macro "Create Assignment Matrices" (Args)

    RunMacro("Directionality", Args)
    // TODO: update this once Ashish changes the airport code
    // RunMacro("Add Airport Trips", Args)
    RunMacro("Collapse Auto Modes", Args)
    RunMacro("Occupancy", Args)
    RunMacro("Collapse Purposes", Args)
    RunMacro("Add CVs and Trucks", Args)
    // TODO needs testing
    // RunMacro("Add Externals", Args)

    return(1)
endmacro

/*
Convert from PA to OD format for auto modes
*/

Macro "Directionality" (Args)

    trip_dir = Args.[Output Folder] + "/resident/trip_tables"
    dir_factor_file = Args.DirectionFactors
    iter = Args.FeedbackIteration
    assn_dir = Args.[Output Folder] + "/assignment/roadway/iter_" + String(iter)

    fac_vw = OpenTable("dir", "CSV", {dir_factor_file})
    rh = GetFirstRecord(fac_vw + "|", )
    auto_modes = {"sov", "hov2", "hov3", "auto_pay", "other_auto"}
    while rh <> null do
        trip_type = fac_vw.trip_type
        period = fac_vw.tod
        pa_factor = fac_vw.pa_fac

        pa_mtx_file = trip_dir + "/pa_per_trips_" + trip_type + "_" + period + ".mtx"
        od_mtx_file = assn_dir + "/od_per_trips_" + trip_type + "_" + period + ".mtx"
        CopyFile(pa_mtx_file, od_mtx_file)

        mtx = CreateObject("Matrix", od_mtx_file)
        // EK12 only has hov2 and hov3 cores at this point. Standardize the
        // matrix here so that all further procedures can be simpler.
        if trip_type = "W_HB_EK12_All" then do
            mtx.AddCores({"sov", "auto_pay", "other_auto"})
        end
        cores = mtx.GetCores()
        t_mtx = mtx.Transpose()
        t_cores = t_mtx.GetCores()
        for mode in auto_modes do
            cores.(mode) := cores.(mode) * pa_factor + t_cores.(mode) * (1 - pa_factor)
        end

        // Drop non-auto modes (these remain PA format)
        core_names = mtx.GetCoreNames()
        for core_name in core_names do
            if auto_modes.position(core_name) = 0 then mtx.DropCores({core_name})
        end
        
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
    iter = Args.FeedbackIteration
    assn_dir = Args.[Output Folder] + "/assignment/roadway/iter_" + String(iter)

    RunMacro("Create Directory", assn_dir)

    // Which trip type and segment to use for modal probabilities
    trip_type = "N_HB_OD_Long"
    segment = "vs"
    
    air_mtx = CreateObject("Matrix", out_dir + "/airport/Airport_Trips.mtx")
    for period in periods do
        mc_mtx_file = mc_dir + "/probabilities/probability_" + trip_type + "_" + segment + "_" + period + ".mtx"
        mc_mtx = CreateObject("Matrix", mc_mtx_file)
        mc_cores = mc_mtx.GetCores()
        res_mtx_file = trip_dir + "/od_per_trips_" + trip_type + "_" + period + ".mtx"
        out_mtx_file = assn_dir + "/od_per_trips_" + trip_type + "_" + period + ".mtx"
        CopyFile(res_mtx_file, out_mtx_file)
        out_mtx = CreateObject("Matrix", out_mtx_file)

        air_core = air_mtx.GetCore("Trips_" + period)
        mode_names = mc_mtx.GetCoreNames()
        out_cores = out_mtx.GetCores()
        for mode in mode_names do
            out_cores.(mode) := nz(out_cores.(mode)) + air_core * mc_cores.(mode)
        end
    end
endmacro

/*
Collapse auto_pay and other_auto into sov/hov2/hov3
*/

Macro "Collapse Auto Modes" (Args)
    
    shares_file = Args.OtherShares
    periods = Args.periods
    iter = Args.FeedbackIteration
    assn_dir = Args.[Output Folder] + "/assignment/roadway/iter_" + String(iter)

    fac_vw = OpenTable("shares", "CSV", {shares_file})
    rh = GetFirstRecord(fac_vw + "|", )
    while rh <> null do
        trip_type = fac_vw.trip_type
        sov_fac = fac_vw.sov
        hov2_fac = fac_vw.hov2
        hov3_fac = fac_vw.hov3

        parts = ParseString(trip_type, "_")
        homebased = parts[2]
// TODO: remove. This is just for testing until the NHB matrices are ready
if homebased = "NH" then goto skip
        if homebased = "HB"
            then cores_to_collapse = {"auto_pay", "other_auto"}
            else cores_to_collapse = {"auto_pay"}

        for period in periods do
            mtx_file = assn_dir + "/od_per_trips_" + trip_type + "_" + period + ".mtx"
            
            mtx = CreateObject("Matrix", mtx_file)
            cores = mtx.GetCores()
            for core_to_collapse in cores_to_collapse do
                cores.sov := cores.sov + cores.(core_to_collapse) * sov_fac
                cores.hov2 := cores.hov2 + cores.(core_to_collapse) * hov2_fac
                cores.hov3 := cores.hov3 + cores.(core_to_collapse) * hov3_fac
            end
            mtx.DropCores({"auto_pay", "other_auto"})
        end
// TODO: remove. This is just for testing until the NHB matrices are ready
skip:        
        rh = GetNextRecord(fac_vw + "|", rh, )
    end
    CloseView(fac_vw)
endmacro

/*
Once the auto person trips have been collapsed into sov, hov2, and hov3, this
converts from person trips to vehicle trips by applying occupancy factors.
*/

Macro "Occupancy" (Args)

    factor_file = Args.HOV3OccFactors
    periods = Args.periods
    iter = Args.FeedbackIteration
    assn_dir = Args.[Output Folder] + "/assignment/roadway/iter_" + String(iter)

    fac_vw = OpenTable("factors", "CSV", {factor_file})
    
    rh = GetFirstRecord(fac_vw + "|", )
    while rh <> null do
        trip_type = fac_vw.trip_type
        period = fac_vw.tod
        hov3_factor = fac_vw.hov3

// TODO: remove. This is just for testing until the NHB matrices are ready
parts = ParseString(trip_type, "_")
homebased = parts[2]
if homebased = "NH" then goto skip

        per_mtx_file = assn_dir + "/od_per_trips_" + trip_type + "_" + period + ".mtx"
        veh_mtx_file = assn_dir + "/od_veh_trips_" + trip_type + "_" + period + ".mtx"
        CopyFile(per_mtx_file, veh_mtx_file)
        mtx = CreateObject("Matrix", veh_mtx_file)
        cores = mtx.GetCores()
        cores.hov2 := cores.hov2 / 2
        cores.hov3 := cores.hov3 / hov3_factor
// TODO: remove. This is just for testing until the NHB matrices are ready
skip:
        rh = GetNextRecord(fac_vw + "|", rh, )
    end
    CloseView(fac_vw)
endmacro

/*
The next step is to collapse trip purposes such that we have a single
matrix for each period. This will contain sov, hov2, hov3, and also transit
trips.
*/

Macro "Collapse Purposes" (Args)

    iter = Args.FeedbackIteration
    assn_dir = Args.[Output Folder] + "/assignment/roadway/iter_" + String(iter)
    periods = Args.periods

    trip_types = RunMacro("Get All Res Trip Types", Args)

    for period in periods do

        // Create the final matrix for the period using the first trip type matrix
        mtx_file = assn_dir + "/od_veh_trips_" + trip_types[1] + "_" + period + ".mtx"
        out_file = assn_dir + "/od_veh_trips_" + period + ".mtx"
        CopyFile(mtx_file, out_file)
        out_mtx = CreateObject("Matrix", out_file)
        out_cores = out_mtx.GetCores()

        // Add the remaining matrices to the output matrix
        for t = 2 to trip_types.length do
            trip_type = trip_types[t]

            mtx_file = assn_dir + "/od_veh_trips_" + trip_type + "_" + period + ".mtx"
            mtx = CreateObject("Matrix", mtx_file)
            cores = mtx.GetCores()
            core_names = mtx.GetCoreNames()
            for core_name in core_names do
                out_cores.(core_name) := nz(out_cores.(core_name)) + nz(cores.(core_name))
            end
        end
    end
endmacro

/*

*/

Macro "Add CVs and Trucks" (Args)

    iter = Args.FeedbackIteration
    assn_dir = Args.[Output Folder] + "/assignment/roadway/iter_" + String(iter)
    cv_dir = Args.[Output Folder] + "/cv"
    periods = Args.periods

    for period in periods do
        trip_mtx_file = assn_dir + "/od_veh_trips_" + period + ".mtx"
        trip_mtx = CreateObject("Matrix", trip_mtx_file)
        cv_mtx_file = cv_dir + "/cv_gravity_" + period + ".mtx"
        cv_mtx = CreateObject("Matrix", cv_mtx_file)
        cv_cores = cv_mtx.GetCores()
        cv_core_names = cv_mtx.GetCoreNames()
        trip_mtx.AddCores(cv_core_names)
        trip_cores = trip_mtx.GetCores()
        for name in cv_core_names do
            trip_cores.(name) := cv_cores.(name)
        end
    end
endmacro

/*

*/

Macro "Add Externals" (Args)

    iter = Args.FeedbackIteration
    assn_dir = Args.[Output Folder] + "/assignment/roadway/iter_" + String(iter)
    ext_dir = Args.[Output Folder] + "/externals"
    periods = Args.periods

    ee_mtx_file = ext_dir + "/ee_trips.mtx"
    ee_mtx = CreateObject("Matrix", ee_mtx_file)
    ee_cores = ee_mtx.GetCores()
    ee_core_names = ee_mtx.GetCoreNames()

    ie_mtx_file = ext_dir + "/ie_trips.mtx"
    ie_mtx = CreateObject("Matrix", ie_mtx_file)
    ie_cores = ie_mtx.GetCores()
    ie_core_names = ie_mtx.GetCoreNames()

    for i = 1 to ee_core_names.length do
        ee_core_name = ee_core_names[i]
        ie_core_name = ie_core_names[i]

        period = Right(ee_core_name, 2)
        trip_mtx_file = assn_dir + "/od_veh_trips_" + period + ".mtx"
        trip_mtx = CreateObject("Matrix", trip_mtx_file)
        trip_mtx.AddCores(ee_core_name)
        trip_mtx.AddCores(ie_core_name)
        trip_cores = trip_mtx.GetCores()
        // The ee matrix only contains external centroids
        trip_mtx.UpdateCore(trip_cores.(ee_core_name), ee_cores.(ee_core_name))
        // The ie matrix contains all centroids
        trip_cores.(ie_core_name) := trip_cores.(ie_core_name) + ie_cores.(ie_core_name)
    end
endmacro