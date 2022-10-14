/*
The macros in this script stitch together all the various travel markets
into four assignment matrices (one for each period). Along the way,
trip conservation snapshots are taken to help identify if trips are being
lost during the conversion.
*/

Macro "Create Assignment Matrices" (Args)

    RunMacro("HB Collapse Auto Modes", Args)
    RunMacro("HB Apply Parking Probabilities", Args)
    RunMacro("NHB Collapse Auto Modes", Args)
    RunMacro("NHB Apply Parking Probabilities", Args)
    RunMacro("HB Directionality", Args)
    RunMacro("Add Airport Trips", Args)
    RunMacro("HB Occupancy", Args)
    RunMacro("HB Collapse Trip Types", Args)
    RunMacro("HB Remove Interim Matrices", Args)
    RunMacro("NHB Collapse Matrices and Occupancy", Args)
    RunMacro("Add CVs and Trucks", Args)
    RunMacro("Add Externals", Args)
    RunMacro("Add University", Args)

    return(1)
endmacro

/*
Convert from PA to OD format for auto modes
*/

Macro "HB Directionality" (Args)

    trip_dir = Args.[Output Folder] + "/resident/trip_matrices"
    dir_factor_file = Args.DirectionFactors
    assn_dir = Args.[Output Folder] + "/assignment/roadway"
    periods = RunMacro("Get Unconverged Periods", Args)

    fac_vw = OpenTable("dir", "CSV", {dir_factor_file})
    rh = GetFirstRecord(fac_vw + "|", )
    auto_modes = {"sov", "hov2", "hov3"}
    while rh <> null do
        trip_type = fac_vw.trip_type
        period = fac_vw.tod
        pa_factor = fac_vw.pa_fac

        if periods.position(period) = 0 then goto skip

        pa_mtx_file = trip_dir + "/pa_per_trips_" + trip_type + "_" + period + ".mtx"
        od_mtx_file = assn_dir + "/od_per_trips_" + trip_type + "_" + period + ".mtx"
        CopyFile(pa_mtx_file, od_mtx_file)

        mtx = CreateObject("Matrix", od_mtx_file)

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
        
        skip:
        rh = GetNextRecord(fac_vw + "|", rh, )
    end
    CloseView(fac_vw)

    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/0 hb trips.csv"
    RunMacro("Trip Conservation Snapshot", trip_dir, out_file)
    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/1 after Directionality.csv"
    RunMacro("Trip Conservation Snapshot", assn_dir, out_file)
endmacro

/*
Adds the airport auto trips to the resident OD matrices
*/

Macro "Add Airport Trips" (Args)
    
    periods = RunMacro("Get Unconverged Periods", Args)
    out_dir = Args.[Output Folder]
    trip_dir = out_dir + "/resident/trip_matrices"
    assn_dir = Args.[Output Folder] + "/assignment/roadway"
    air_dir = out_dir + "/airport"
    shares_file = Args.HBOtherShares

    // Which trip type to add airport trips to
    trip_type = "N_HB_OD_Long"
    
    for period in periods do
        air_mtx_file = air_dir + "/airport_auto_trips_" + period + ".mtx"
        air_mtx = CreateObject("Matrix", air_mtx_file)
        od_mtx_file = assn_dir + "/od_per_trips_" + trip_type + "_" + period + ".mtx"
        od_mtx = CreateObject("Matrix", od_mtx_file)

        // First collapse auto_pay and other_auto into sov/hov2/hov3 for airport trips
        fac_vw = OpenTable("shares", "CSV", {shares_file})
        rh = GetFirstRecord(fac_vw + "|", )
        while rh <> null do
            trip_type2 = fac_vw.trip_type
            if trip_type2 <> trip_type then goto next_record
            sov_fac = fac_vw.sov
            hov2_fac = fac_vw.hov2
            hov3_fac = fac_vw.hov3

            cores_to_collapse = {"auto_pay", "other_auto"}

            cores = air_mtx.GetCores()
            for core_to_collapse in cores_to_collapse do
                cores.sov := cores.sov + nz(cores.(core_to_collapse)) * sov_fac
                cores.hov2 := cores.hov2 + nz(cores.(core_to_collapse)) * hov2_fac
                cores.hov3 := cores.hov3 + nz(cores.(core_to_collapse)) * hov3_fac
            end
            air_mtx.DropCores({"auto_pay", "other_auto"})
        
        next_record: 
            rh = GetNextRecord(fac_vw + "|", rh, )
        end
        CloseView(fac_vw)

        // Then add airport trips
        core_names = air_mtx.GetCoreNames()
        for core_name in core_names do
            air_core = air_mtx.GetCore(core_name)
            od_core = od_mtx.GetCore(core_name)
            od_core := nz(od_core) + nz(air_core)
        end
    end

    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/0 airport trips.csv"
    RunMacro("Trip Conservation Snapshot", air_dir, out_file)
    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/2 after Add Airport Trips.csv"
    RunMacro("Trip Conservation Snapshot", assn_dir, out_file)
endmacro

/*
Collapse auto_pay and other_auto into sov/hov2/hov3
*/

Macro "HB Collapse Auto Modes" (Args)
    
    shares_file = Args.HBOtherShares
    periods = RunMacro("Get Unconverged Periods", Args)
    out_dir = Args.[Output Folder]
    trip_dir = out_dir + "/resident/trip_matrices"

    // HB Trips
    fac_vw = OpenTable("shares", "CSV", {shares_file})
    rh = GetFirstRecord(fac_vw + "|", )
    while rh <> null do
        trip_type = fac_vw.trip_type
        sov_fac = fac_vw.sov
        hov2_fac = fac_vw.hov2
        hov3_fac = fac_vw.hov3

        cores_to_collapse = {"auto_pay", "other_auto"}

        for period in periods do
            trip_mtx_file = trip_dir + "/pa_per_trips_" + trip_type + "_" + period + ".mtx"
            
            mtx = CreateObject("Matrix", trip_mtx_file)
            cores = mtx.GetCores()
            for core_to_collapse in cores_to_collapse do
                if cores.sov <> null then
                    cores.sov := cores.sov + nz(cores.(core_to_collapse)) * sov_fac
                cores.hov2 := cores.hov2 + nz(cores.(core_to_collapse)) * hov2_fac
                cores.hov3 := cores.hov3 + nz(cores.(core_to_collapse)) * hov3_fac
            end
            mtx.DropCores({"auto_pay", "other_auto"})
        end
        rh = GetNextRecord(fac_vw + "|", rh, )
    end
    CloseView(fac_vw)

    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/3 after HB Collapse Auto Modes.csv"
    RunMacro("Trip Conservation Snapshot", trip_dir, out_file)
endmacro

/*
Once the auto person trips have been collapsed into sov, hov2, and hov3, this
converts from person trips to vehicle trips by applying occupancy factors.
*/

Macro "HB Occupancy" (Args)

    factor_file = Args.HBHOV3OccFactors
    periods = RunMacro("Get Unconverged Periods", Args)
    assn_dir = Args.[Output Folder] + "/assignment/roadway"

    fac_vw = OpenTable("factors", "CSV", {factor_file})
    
    rh = GetFirstRecord(fac_vw + "|", )
    while rh <> null do
        trip_type = fac_vw.trip_type
        period = fac_vw.tod
        hov3_factor = fac_vw.hov3

        if periods.position(period) = 0 then goto skip

        per_mtx_file = assn_dir + "/od_per_trips_" + trip_type + "_" + period + ".mtx"
        veh_mtx_file = assn_dir + "/od_veh_trips_" + trip_type + "_" + period + ".mtx"
        CopyFile(per_mtx_file, veh_mtx_file)
        mtx = CreateObject("Matrix", veh_mtx_file)
        cores = mtx.GetCores()
        cores.hov2 := cores.hov2 / 2
        cores.hov3 := cores.hov3 / hov3_factor

        skip:
        rh = GetNextRecord(fac_vw + "|", rh, )
    end
    CloseView(fac_vw)

    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/4 after HB Occupancy.csv"
    RunMacro("Trip Conservation Snapshot", assn_dir, out_file)
endmacro

/*
The next step is to collapse trip purposes such that we have a single
matrix for each period. This will contain sov, hov2, hov3, and also transit
trips.
*/

Macro "HB Collapse Trip Types" (Args)

    assn_dir = Args.[Output Folder] + "/assignment/roadway"
    periods = RunMacro("Get Unconverged Periods", Args)

    trip_types = RunMacro("Get HB Trip Types", Args)

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

    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/5 after HB Collapse Trip Types.csv"
    RunMacro("Trip Conservation Snapshot", assn_dir, out_file)
endmacro

/*
Simple macro that removes the interim matrices created in this folder to save
space. For debugging these steps, comment out this macro in "Create Assignment
Matrices".

Note: if parallelizing the entire feedback loop, this has to change
*/

Macro "HB Remove Interim Matrices" (Args)

    assn_dir = Args.[Output Folder] + "/assignment/roadway"

    files = RunMacro("Catalog Files", {dir: assn_dir, ext: "mtx"})

    files_to_keep = {
        "od_veh_trips_AM",
        "od_veh_trips_MD",
        "od_veh_trips_PM",
        "od_veh_trips_NT"
    }

    for file in files do
        {, , name, } = SplitPath(file)
        if files_to_keep.position(name) = 0 then DeleteFile(file)
    end

    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/6 after HB Remove Interim Matrices.csv"
    RunMacro("Trip Conservation Snapshot", assn_dir, out_file)
endmacro

/*
NHB auto_pay trips are converted to sov, hov2, and hov3 vehicle classes
*/

Macro "NHB Collapse Auto Modes" (Args)
    shares_file = Args.NHBOtherShares
    out_dir = Args.[Output Folder]
    nhb_dir = out_dir + "/resident/nhb/dc/trip_matrices"
    periods = RunMacro("Get Unconverged Periods", Args)

    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/0 nhb trips.csv"
    RunMacro("Trip Conservation Snapshot", nhb_dir, out_file)

    // Distribute auto_pay to other modes
    share_vw = OpenTable("shares", "CSV", {shares_file})
    share_data = GetDataVectors(
        share_vw + "|",
        {"tour_type", "sov", "hov2", "hov3"},
        {OptArray: true}
    )
    CloseView(share_vw)
    nhb_mtxs = RunMacro("Catalog Files", {dir: nhb_dir, ext: "mtx"})
    for nhb_mtx_file in nhb_mtxs do
        
        // Skip everything but auto_pay matrices. Also skip converged periods.
        {, , name, } = SplitPath(nhb_mtx_file)
        parts = ParseString(name, "_")
        if parts[2] = "transit" or parts[2] = "walkbike" then continue
        if parts[3] <> "auto" then continue
        period = parts[5]
        if periods.position(period) = 0 then continue
        
        period = parts[5]
        tour_type = parts[2]
        lookup = if tour_type = "n" then "NonWork" else "Work"
        pos = share_data.tour_type.position(lookup)
        
        mtx_file = nhb_dir + "/NHB_" + tour_type + "_auto_pay_" + period + ".mtx"
        mtx = CreateObject("Matrix", mtx_file)
        to_modes = {"sov", "hov2", "hov3"}
        mtx.AddCores(to_modes)
        cores = mtx.GetCores()
        for mode in to_modes do
            pct = share_data.(mode)
            pct = pct[pos]

            cores.(mode) := nz(cores.Total) * pct
        end
    end

    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/7 nhb trips after NHB Collapse Auto Modes.csv"
    RunMacro("Trip Conservation Snapshot", nhb_dir, out_file)
endmacro

/*
Add the NHB trips into the assignment matrices. This requires a conversion from
person to vehicle trips.
*/

Macro "NHB Collapse Matrices and Occupancy" (Args)
    hov3_file = Args.NHBHOV3OccFactors
    out_dir = Args.[Output Folder]
    nhb_dir = out_dir + "/resident/nhb/dc/trip_matrices"
    assn_dir = Args.[Output Folder] + "/assignment/roadway"
    periods = RunMacro("Get Unconverged Periods", Args)

    // Add NHB trips to OD assignment matrices (and convert to veh trips)
    hov3_vw = OpenTable("hov3", "CSV", {hov3_file})
    nhb_mtxs = RunMacro("Catalog Files", {dir: nhb_dir, ext: "mtx"})
    for nhb_mtx_file in nhb_mtxs do
        
        // Skip transit and walkbike matrices and any converged periods
        {, , name, } = SplitPath(nhb_mtx_file)
        parts = ParseString(Lower(name), "_")
        if parts[2] = "transit" or parts[2] = "walkbike" then continue
        tour_type = parts[2]
        if parts[3] = "auto" then auto_pay = "true" else auto_pay = "false"
        if auto_pay then do
            mode = "auto_pay"
            period = parts[5]
        end else do
            mode = parts[3]
            period = parts[4]
        end
        if periods.position(period) = 0 then continue

        nhb_mtx = CreateObject("Matrix", nhb_mtx_file)
        nhb_cores = nhb_mtx.GetCores()

        // Get vehicle factor and convert to veh trips
        if mode = "sov" then occ_rate = 1
        else if mode = "hov2" then occ_rate = 2
        else do
            SetView(hov3_vw)
            n = SelectByQuery(
                "sel", "several", 
                "Select * where tour_type = '" + Upper(tour_type) + "' and tod = '" + Upper(period) + "'"
            )
            if n = 0 then Throw(
                "Trying to add NHB trips into assignment matrix.\n" +
                "HOV3 factor not found in lookup table."
            )
            occ_rate = GetDataVector(hov3_vw + "|sel", "hov3", )
            occ_rate = occ_rate[1]
        end
        // auto_pay matrices have four cores while all others only have 1
        if auto_pay then do
            nhb_cores.hov2 := nhb_cores.hov2 / 2
            nhb_cores.hov3 := nhb_cores.hov3 / occ_rate
        end else nhb_cores.Total := nhb_cores.Total / occ_rate

        trans_mtx = nhb_mtx.Transpose()
        nhb_t_cores = trans_mtx.GetCores()

        assn_mtx_file = assn_dir + "/od_veh_trips_" + period + ".mtx"
        assn_mtx = CreateObject("Matrix", assn_mtx_file)
        assn_cores = assn_mtx.GetCores()
        
        // For assignment, auto_pay trips need to count the driver for purposes
        // of hov lane restrictions. This means:
        // sov -> hov2
        // hov2 -> hov3
        // hov3 -> hov3
        // directionality is assumed to be 50/50
        if auto_pay then do
            assn_cores.hov2 := assn_cores.hov2 + (nhb_cores.sov + nhb_t_cores.sov) / 2
            assn_cores.hov3 := assn_cores.hov3 + (nhb_cores.hov2 + nhb_t_cores.hov2) / 2
            assn_cores.hov3 := assn_cores.hov3 + (nhb_cores.hov3 + nhb_t_cores.hov3) / 2
        end else do
            assn_cores.(mode) := assn_cores.(mode) + (nhb_cores.Total + nhb_t_cores.Total) / 2
        end
    end
    CloseView(hov3_vw)

    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/8 after NHB Collapse Matrices and Occupancy.csv"
    RunMacro("Trip Conservation Snapshot", assn_dir, out_file)
endmacro

/*

*/

Macro "Add CVs and Trucks" (Args)

    assn_dir = Args.[Output Folder] + "/assignment/roadway"
    cv_dir = Args.[Output Folder] + "/cv"
    periods = RunMacro("Get Unconverged Periods", Args)

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

    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/0 cv and truck trips.csv"
    RunMacro("Trip Conservation Snapshot", cv_dir, out_file)
    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/9 after Add CVs and Trucks.csv"
    RunMacro("Trip Conservation Snapshot", assn_dir, out_file)
endmacro


/*

*/

Macro "Add Externals" (Args)

    assn_dir = Args.[Output Folder] + "/assignment/roadway"
    ext_dir = Args.[Output Folder] + "/external"
    periods = RunMacro("Get Unconverged Periods", Args)

    ee_mtx_file = ext_dir + "/ee_trips.mtx"
    ee_mtx = CreateObject("Matrix", ee_mtx_file)
    ee_cores = ee_mtx.GetCores()
    ee_core_names = ee_mtx.GetCoreNames()

    ie_mtx_file = ext_dir + "/ie_od_trips.mtx"
    ie_mtx = CreateObject("Matrix", ie_mtx_file)
    ie_cores = ie_mtx.GetCores()
    ie_core_names = ie_mtx.GetCoreNames()

    for i = 1 to ee_core_names.length do
        ee_core_name = ee_core_names[i]
        ie_core_name = ie_core_names[i]

        // Currently treating all external auto as sov, but could split into occupancy classes in future given data
        // ee/ie core names look like "EE_AUTO_AM" or "IEEI_CVMUT_MD"
        parts = ParseString(ee_core_name, "_")
        period = parts[3]
        if periods.position(period) = 0 then continue
        if parts[2] = "AUTO" then core_name = "sov"
        if parts[2] = "CVSUT" then core_name = "SUT"
        if parts[2] = "CVMUT" then core_name = "MUT"

        trip_mtx_file = assn_dir + "/od_veh_trips_" + period + ".mtx"
        trip_mtx = CreateObject("Matrix", trip_mtx_file)
        trip_cores = trip_mtx.GetCores()
        // The ee matrix only contains external centroids
        trip_mtx.UpdateCore({CoreName: core_name, SourceCores: ee_cores.(ee_core_name)})
        // The ie matrix contains all centroids
        trip_cores.(core_name) := nz(trip_cores.(core_name)) + nz(ie_cores.(ie_core_name))
    end

    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/0 external trips.csv"
    RunMacro("Trip Conservation Snapshot", ext_dir, out_file)
    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/12 after Add Externals.csv"
    RunMacro("Trip Conservation Snapshot", assn_dir, out_file)
endmacro

/*

*/

Macro "Add University" (Args)

    assn_dir = Args.[Output Folder] + "/assignment/roadway"
    univ_dir = Args.[Output Folder] + "/university"
    periods = RunMacro("Get Unconverged Periods", Args)

    for period in periods do
        univ_mtx_file = univ_dir + "/university_trips_" + period + ".mtx"
        univ_mtx = CreateObject("Matrix", univ_mtx_file)

        trip_mtx_file = assn_dir + "/od_veh_trips_" + period + ".mtx"
        trip_mtx = CreateObject("Matrix", trip_mtx_file)

        // "auto" core from university model trips is put into "sov" in od trips
        univ_core = univ_mtx.GetCore("auto")
        trip_core = trip_mtx.GetCore("sov")

        trip_core := nz(trip_core) + nz(univ_core)
    end

    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/0 university trips.csv"
    RunMacro("Trip Conservation Snapshot", univ_dir, out_file)
    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/13 after Add University.csv"
    RunMacro("Trip Conservation Snapshot", assn_dir, out_file)
endmacro