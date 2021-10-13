/*

*/

Macro "Create Assignment Matrices" (Args)

    RunMacro("Directionality", Args)
    RunMacro("Add Airport Trips", Args)
    RunMacro("HB Collapse Auto Modes", Args)
    RunMacro("HB Occupancy", Args)
    RunMacro("HB Collapse Trip Types", Args)
    RunMacro("HB Remove Interim Matrices", Args)
    RunMacro("NHB Collapse Auto Modes", Args)
    RunMacro("NHB Collapse Matrices and Occupancy", Args)
    RunMacro("Add CVs and Trucks", Args)
    RunMacro("VOT Split", Args)
    RunMacro("VOT Aggregation", Args)
    RunMacro("Add Externals", Args)

    return(1)
endmacro

/*
Convert from PA to OD format for auto modes
*/

Macro "Directionality" (Args)

    trip_dir = Args.[Output Folder] + "/resident/trip_matrices"
    dir_factor_file = Args.DirectionFactors
    assn_dir = Args.[Output Folder] + "/assignment/roadway"
    RunMacro("Create Directory", assn_dir)

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

    // Which trip type to add airport trips to
    trip_type = "N_HB_OD_Long"
    
    for period in periods do
        air_mtx_file = air_dir + "/airport_auto_trips_" + period + ".mtx"
        air_mtx = CreateObject("Matrix", air_mtx_file)
        od_mtx_file = assn_dir + "/od_per_trips_" + trip_type + "_" + period + ".mtx"
        od_mtx = CreateObject("Matrix", od_mtx_file)

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
    assn_dir = Args.[Output Folder] + "/assignment/roadway"

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
        rh = GetNextRecord(fac_vw + "|", rh, )
    end
    CloseView(fac_vw)

    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/3 after HB Collapse Auto Modes.csv"
    RunMacro("Trip Conservation Snapshot", assn_dir, out_file)
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

        per_mtx_file = assn_dir + "/od_per_trips_" + trip_type + "_" + period + ".mtx"
        veh_mtx_file = assn_dir + "/od_veh_trips_" + trip_type + "_" + period + ".mtx"
        CopyFile(per_mtx_file, veh_mtx_file)
        mtx = CreateObject("Matrix", veh_mtx_file)
        cores = mtx.GetCores()
        cores.hov2 := cores.hov2 / 2
        cores.hov3 := cores.hov3 / hov3_factor
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

Note: if parallelizing more than assignment by time period, this has to change
*/

Macro "HB Remove Interim Matrices" (Args)

    assn_dir = Args.[Output Folder] + "/assignment/roadway"

    files = RunMacro("Catalog Files", assn_dir, "mtx")

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
    nhb_mtxs = RunMacro("Catalog Files", nhb_dir, "mtx")
    for nhb_mtx_file in nhb_mtxs do
        
        // Skip everything but auto_pay matrices
        {, , name, } = SplitPath(nhb_mtx_file)
        parts = ParseString(name, "_")
        if parts[2] = "transit" or parts[2] = "walkbike" then continue
        if parts[3] <> "auto" then continue
        
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

    // Add NHB trips to OD assignment matrices (and convert to veh trips)
    hov3_vw = OpenTable("hov3", "CSV", {hov3_file})
    nhb_mtxs = RunMacro("Catalog Files", nhb_dir, "mtx")
    for nhb_mtx_file in nhb_mtxs do
        
        // Skip transit and walkbike matrices
        {, , name, } = SplitPath(nhb_mtx_file)
        parts = ParseString(name, "_")
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

        nhb_mtx = CreateObject("Matrix", nhb_mtx_file)
        nhb_cores = nhb_mtx.GetCores()

        // Get vehicle factor and convert to veh trips
        if mode = "sov" then occ_rate = 1
        else if mode = "hov2" then occ_rate = 2
        else do
            SetView(hov3_vw)
            n = SelectByQuery(
                "sel", "several", 
                "Select * where tour_type = '" + Upper(tour_type) + "' and tod = '" + period + "'"
            )
            if n = 0 then Throw(
                "Trying to add NHB trips into assignment matrix./n" +
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

        // ee/ie core names look like "EE_AUTO_AM" or "IEEI_CVMUT_MD"
        parts = ParseString(ee_core_name, "_")
        period = parts[3]
        if parts[2] = "AUTO" then core_name = "sov_VOT2"
        if parts[2] = "CVSUT" then core_name = "SUT_VOT2"
        if parts[2] = "CVMUT" then core_name = "MUT_VOT3"

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
    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/10 after Add Externals.csv"
    RunMacro("Trip Conservation Snapshot", assn_dir, out_file)
endmacro

/*
This borrows the NCSTM approach to split OD matrices into distinct values of
time. This is based both on the distance of the trip and the average HH incomes
in the origin and destination zones.
*/

Macro "VOT Split" (Args)

    se_file = Args.SE
    vot_params = Args.[Input Folder] + "/assignment/vot_params.csv"
    periods = RunMacro("Get Unconverged Periods", Args)
    assn_dir = Args.[Output Folder] + "/assignment/roadway"
    skim_dir = Args.[Output Folder] + "/skims/roadway"

    p = RunMacro("Read Parameter File", {file: vot_params})
    veh_classes = {"sov", "hov2", "hov3", "CV", "SUT", "MUT"}
    auto_classes = {"sov", "hov2", "hov3", "CV"}

    se_vw = OpenTable("se", "FFB", {se_file})
    {v_hh, v_inc} = GetDataVectors(
        se_vw + "|", {"HH","Median_Inc"}, 
        {{"Sort Order",{{"TAZ","Ascending"}}}}
    )

    for period in periods do
        if period = "AM" or period = "PM"
            then pkop = "pk"
            else pkop = "op"
        mtx_file = assn_dir + "/od_veh_trips_" + period + ".mtx"
        skim_file = skim_dir + "/skim_sov_" + period + ".mtx"
        
        skim = CreateObject("Matrix", skim_file)
        length_skim = skim.data.cores.("Length (Skim)")

        // Calculate weighted income
        output = CreateObject("Matrix", mtx_file)
        output.AddCores({"hh", "wgtinc", "otemp", "dtemp"})
        cores = output.data.cores
        cores.otemp := v_hh
        v_hh.rowbased = "false"
        cores.dtemp := v_hh
        v_hh.rowbased = true
        cores.hh := cores.otemp + cores.dtemp
        v_tothhinc = v_inc/100 * v_hh
		cores.otemp    := v_tothhinc
		v_tothhinc.rowbased = false
		cores.dtemp    := v_tothhinc
		v_tothhinc.rowbased = true
		cores.wgtinc    := (cores.otemp + cores.dtemp) / cores.hh
        output.DropCores({"hh", "otemp", "dtemp"})

        output.AddCores({"lognorm", "zscore"})
        for veh_class in veh_classes do
            
            // Auto classes
            if auto_classes.position(veh_class) > 0 then do
                meanvot = p.(pkop + "_meanvot")
                targetvot = p.(pkop + "_targetvot")
                costcoef = p.(pkop + "_costcoef")
                meantime = p.(pkop + "_meantime")
                sdtime = p.(pkop + "_sdtime")
                for i = 1 to 5 do
                    votcut = p.("votcut" + i2s(i))
                    out_core = veh_class + "_VOT" + i2s(i)
                    cumu_prob = veh_class + "_VOT" + i2s(i) + "_cumuprob"
                    prob_core = veh_class + "_VOT" + i2s(i) + "_prob"
                    output.AddCores({cumu_prob, prob_core, out_core})
                    cores = output.data.cores

                    // Calculate cumulative probability
                    cores.lognorm := (votcut * costcoef) / (log(cores.wgtinc) * log(10 * length_skim + 5) * 60 * (targetvot/meanvot))
                    cores.zscore := (log(-1 * cores.lognorm) - meantime) / sdtime
                    RunMacro("erf_normdist", output, cumu_prob)

                    // Convert cumulative probability to individual
                    if i = 1 then do
                        cores.(prob_core) := cores.(cumu_prob)
                    end else do
                        prev_cumu = veh_class + "_VOT" + i2s(i - 1) + "_cumuprob"
                        if i = 5 then cores.(prob_core) := 1 - cores.(prev_cumu)
                        else cores.(prob_core) := cores.(cumu_prob) - cores.(prev_cumu)
                    end

                    // Calculate final core
                    cores.(out_core) := cores.(veh_class) * cores.(prob_core)    
                end

                // Cleanup
                for i = 1 to 5 do
                    cumu_prob = veh_class + "_VOT" + i2s(i) + "_cumuprob"
                    prob_core = veh_class + "_VOT" + i2s(i) + "_prob"
                    output.DropCores({prob_core, cumu_prob})
                end
            end

            // Truck Classes
            if veh_class = "SUT" then truck_classes = 3
            else if veh_class = "MUT" then truck_classes = 5
            else truck_classes = 0
            for i = 1 to truck_classes do
                weight = p.(Lower(veh_class) + "wgt" + i2s(i))
                out_core = veh_class + "_VOT" + i2s(i)
                output.AddCores({out_core})
                cores = output.data.cores
                cores.(out_core) := cores.(veh_class) * weight
            end
        end
        output.DropCores({"lognorm", "zscore", "wgtinc"})
        output.DropCores(veh_classes)
    end

    CloseView(se_vw)

    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/11 after VOT Split.csv"
    RunMacro("Trip Conservation Snapshot", assn_dir, out_file)
endmacro

/*
Helper function for "VOT Split"

Calculates NORMDIST(z) by using an error function approximation (modified using Horner's method)
https://www.codeproject.com/Articles/408214/Excel-Function-NORMSDIST-z_score
*/

Macro "erf_normdist" (matrix, out_corename)

    matrix.AddCores({"sign", "x", "t", "erf", "normdist"})
    cores = matrix.data.cores

	//Calculate erf(x)
	cores.x := Abs(cores.zscore)/Sqrt(2)
	a1 = 0.254829592
	a2 = -0.284496736
	a3 = 1.421413741
	a4 = -1.453152027
	a5 = 1.061405429
	p = 0.3275911
	cores.x := Abs(cores.x)
	cores.t := 1 / (1 + p * cores.x)
	cores.erf := 1 - ((((((a5 * cores.t + a4) * cores.t) + a3) * cores.t + a2) * cores.t) + a1) * cores.t * Exp(-1 * cores.x * cores.x)
	//Calculate normdist(zscore)
	cores.sign := if cores.zscore < 0 then -1 else 1
	cores.normdist := 0.5 * (1.0 + cores.sign * cores.erf)
	cores.(out_corename) := cores.normdist

	//Cleanup
    matrix.DropCores({"sign", "x", "t", "erf", "normdist"})
endMacro

/*
The 'VOT Split' macro fully disaggregates values of time based on the NCSTM
approach; however, this leads to a lot of classes and much slower assignments.
This collapses some of the classes. It's a separate macro to make it easy
to disable in the future if desired (e.g. on a faster machine or for a
detailed toll study).
*/

Macro "VOT Aggregation" (Args)

    assn_dir = Args.[Output Folder] + "/assignment/roadway"
    periods = RunMacro("Get Unconverged Periods", Args)

    auto_cores = {"sov", "hov2", "hov3", "CV"}

    for period in periods do
        mtx_file = assn_dir + "/od_veh_trips_" + period + ".mtx"
        mtx = CreateObject("Matrix", mtx_file)
        cores = mtx.GetCores()

        // Collapse auto VOT classes 1-3 into just class 2
        for auto_core in auto_cores do
            core1 = auto_core + "_VOT1"
            core2 = auto_core + "_VOT2"
            core3 = auto_core + "_VOT3"
            cores.(core2) := nz(cores.(core2)) + nz(cores.(core1)) + nz(cores.(core3))
            mtx.DropCores({core1, core3})
        end 
    end

    out_file = Args.[Output Folder] + "/_summaries/trip_conservation/12 after VOT Aggregation.csv"
    RunMacro("Trip Conservation Snapshot", assn_dir, out_file)
endmacro