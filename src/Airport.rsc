/*
Called by flowchart

Generates and distributes airport trips. Because the models are simple and
do not depend on congested times, it can be done outside the feedback loop.
Mode choice for airport trips happens within the feedback loop and uses the
N_HB_OD_Long_vs probabilities.
*/

Macro "Airport" (Args)
    RunMacro("Airport Productions", Args)
    RunMacro("Airport Distribution", Args)
    RunMacro("Airport TOD", Args)
    return(1)
endmacro

/*
Called by flowchart
*/

Macro "Airport MC" (Args)
    RunMacro("Airport Mode Choice", Args)
    RunMacro("Airport Separate Auto and Transit", Args)
    RunMacro("Airport Directionality", Args)
    return(1)
endmacro

/*
Calculate airport productions
*/

Macro "Airport Productions" (Args)
    se_file = Args.SE
    skim_dir = Args.[Output Folder] + "\\skims\\roadway"
    airport_model_file = Args.[Input Folder] + "\\airport\\airport_model.csv"

    se_vw = OpenTable("se", "FFB", {se_file})
    
    data = GetDataVectors(
        se_vw + "|",
        {
            "TAZ",
            "HH_POP",
            "Pct_Worker",
            "PctHighPay",
            "TotalEmp"
        },
        {OptArray: TRUE}
    )

    // find airport taz (one with positive enplanement field)
    SetView(se_vw)
    n = SelectByQuery("airport_taz", "Several", "Select * where Enplanements > 0",)
    airport_zone = GetDataVector(se_vw + "|airport_taz", "TAZ", )
    airport_zone = airport_zone[1]
    airport_enplanement = GetDataVector(se_vw + "|airport_taz", "Enplanements", )
    airport_enplanement = airport_enplanement[1]
    
    taz_vec = data.TAZ
    
    // get distance to airport zone
    skim_mat = skim_dir + "/accessibility_sov_AM.mtx"
    mat = CreateObject("Matrix", skim_mat)
    cores = mat.GetCores()
    distance_array = GetMatrixValues(cores.[Length (Skim)], V2A(taz_vec), {airport_zone})
    cores = null
    mat = null
    
    for i = 1 to distance_array.length do
        dist_to_airport_miles = dist_to_airport_miles + {distance_array[i][1]}
    end
    
    dist_to_airport_miles = A2V(dist_to_airport_miles)
    
    // get variables for regression
    workers = data.HH_POP * data.Pct_Worker/100
    high_paying_jobs = data.TotalEmp * data.PctHighPay/100
    high_paying_jobs_distance = high_paying_jobs * dist_to_airport_miles
    
    // read airport model file for coefficients
    coeffs = RunMacro("Read Parameter File", {
        file: airport_model_file,
        names: "variable",
        values: "coefficient"
    })
    
    // compute airport productions
    airport_productions = coeffs.employment * data.TotalEmp +
    coeffs.high_paying_jobs * high_paying_jobs +
    coeffs.high_paying_jobs_distance * high_paying_jobs_distance +
    coeffs.workers * workers
    
    airport_productions = if (airport_productions < 0) then 0 else airport_productions
    airport_productions = airport_productions * airport_enplanement / airport_productions.sum()
    
    a_fields = {{"AirportProd", "Real", 10, 2, , , , "airport productions"}}
    RunMacro("Add Fields", {view: se_vw, a_fields: a_fields})
    
    SetView(se_vw)
    SetDataVector(se_vw + "|", "AirportProd", airport_productions, )
    
    CloseView(se_vw)
endmacro

/*
There is only one airport zone, so distribution is very simple
*/

Macro "Airport Distribution" (Args)
    se_file = Args.SE
    hwy_dbd = Args.Links
    trips_dir = Args.[Output Folder] + "\\airport"
    periods = Args.periods

    airport_matrix = trips_dir + "/airport_pa_trips.mtx"
    
    se_vw = OpenTable("se", "FFB", {se_file})
    
    SetView(se_vw)
    n = SelectByQuery("airport_taz", "Several", "Select * where Enplanements > 0",)
    airport_zone = GetDataVector(se_vw + "|airport_taz", "TAZ", )
    airport_zone = airport_zone[1]
    
    airport_productions = GetDataVector(se_vw + "|", "AirportProd", )
    
    // create empty matrix from node layer
    {map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd})
    
    SetLayer(nlyr)
    qry = "Select * where Centroid = 1"
    n = SelectByQuery("centroids", "several", qry)
    centroid_ids = GetDataVector(nlyr + "|centroids", "ID", {{"Sort Order", {{"ID", "Ascending"}}}})
    
    obj = CreateObject("Matrix", {Empty: True})
    obj.SetMatrixOptions({
        FileName: airport_matrix,
        MatrixLabel: "Airport Trips",
        Compressed: 1,
        DataType: "Float"})
    opts.RowIds = V2A(centroid_ids)
    opts.ColIds = V2A(centroid_ids)
    opts.MatrixNames = {"Trips"}
    opts.RowIndexName = "TAZ"
    opts.ColIndexName = "TAZ"
    mat = obj.CreateFromArrays(opts)
    
    mc = CreateMatrixCurrency(mat, "Trips", , , )
    rows = V2A(centroid_ids)
    cols = {airport_zone}
    for i = 1 to centroid_ids.length do
        pa_trips = pa_trips + {{airport_productions[i]}}
    end
    SetMatrixValues(mc, rows, cols, {"Copy", pa_trips}, )
    
    mc = null
    mat = null
    CloseView(se_vw)
    CloseMap(map)
endmacro

/*
Split airport trips by time period
*/

Macro "Airport TOD" (Args)
    trips_dir = Args.[Output Folder] + "\\airport"
    tod_file = Args.[Input Folder] + "\\airport\\airport_tod.csv"
    periods = Args.periods
	
    airport_mtx_file = trips_dir + "/airport_pa_trips.mtx"
    
    tod_factors = RunMacro("Read Parameter File", {
        file: tod_file,
        names: "period",
        values: "factor"
    })
    
    for period in periods do 
        factor = tod_factors.(period)
        
        period_mtx_file = Substitute(airport_mtx_file, ".mtx", "_" + period + ".mtx", )
        CopyFile(airport_mtx_file, period_mtx_file)
        
        mat = CreateObject("Matrix", period_mtx_file)
        cores = mat.GetCores()
        
        cores.("Trips") := Nz(cores.("Trips")) * factor
        
        cores = null
        mat = null
    end
    
    DeleteFile(airport_mtx_file)
endmacro

/*
Apply mode choice probabilities to split airport trips by mode.
*/

Macro "Airport Mode Choice" (Args)
    trips_dir = Args.[Output Folder] + "\\airport"
    mc_dir = Args.[Output Folder] + "\\resident\\mode"
    periods = RunMacro("Get Unconverged Periods", Args)
    
    for period in periods do 
        mc_mtx_file = mc_dir + "/probabilities/probability_N_HB_OD_Long_vs_" + period + ".mtx"
        
        airport_mtx_file = trips_dir + "/airport_pa_trips_" + period + ".mtx"
        
        out_mtx_file = trips_dir + "/airport_pa_mode_trips_" + period + ".mtx"
        if GetFileInfo(out_mtx_file) <> null then DeleteFile(out_mtx_file)
        
        CopyFile(mc_mtx_file, out_mtx_file)
        out_mtx = CreateObject("Matrix", out_mtx_file)
        out_cores = out_mtx.GetCores()
        
        mc_mtx = CreateObject("Matrix", mc_mtx_file)
        mc_cores = mc_mtx.GetCores()
        mode_names = mc_mtx.GetCoreNames()
        
        airport_mtx = CreateObject("Matrix", airport_mtx_file)
        airport_cores = airport_mtx.GetCores()
        
        for mode in mode_names do
            out_cores.(mode) := 0
            out_cores.(mode) := nz(airport_cores.("Trips")) * mc_cores.(mode)
        end
        
        out_cores = null
        mc_cores = null
        airport_cores = null
        out_mtx = null
        mc_mtx = null
        airport_mtx = null
    end

endmacro

/*
Separate out auto and transit trip tables
*/

Macro "Airport Separate Auto and Transit" (Args)
    trips_dir = Args.[Output Folder] + "\\airport"
    periods = RunMacro("Get Unconverged Periods", Args)
    
    auto_modes = {"sov", "hov2", "hov3", "auto_pay", "other_auto"}
    
    for period in periods do
        pa_mtx_file = trips_dir + "/airport_pa_mode_trips_" + period + ".mtx"
        auto_mtx_file = trips_dir + "/airport_pa_auto_trips_" + period + ".mtx"
        transit_mtx_file = trips_dir + "/airport_transit_trips_" + period + ".mtx"
        
        mtx = CreateObject("Matrix", pa_mtx_file)
        mtx_cores = mtx.GetCores()
        all_modes = mtx.GetCoreNames()	   
        
        transit_modes = ArrayExclude(all_modes, auto_modes)
        
        matOpts = {{"File Name", transit_mtx_file}, {"Label", "Airport Transit Trips"}, {"File Based", "Yes"}, {"Tables", transit_modes}}
        CopyMatrixStructure({mtx_cores[1][2]}, matOpts)
        
        transit_mtx = CreateObject("Matrix", transit_mtx_file)
        transit_cores = transit_mtx.GetCores()
        
        for transit_mode in transit_modes do
            transit_cores.(transit_mode) := Nz(mtx_cores.(transit_mode))
        end
        
        transit_mtx = null
        transit_cores = null
        mtx_cores = null
        mtx = null
        
        CopyFile(pa_mtx_file, auto_mtx_file)
        
        auto_mtx = CreateObject("Matrix", auto_mtx_file)
        auto_mtx.DropCores(transit_modes)
        auto_mtx.Pack()
        auto_mtx = null
        
        DeleteFile(pa_mtx_file)
    end

endmacro

/*
Convert from PA to OD format for Auto trips
*/

Macro "Airport Directionality" (Args)
    trips_dir = Args.[Output Folder] + "\\airport"
    dir_factor_file = Args.[Input Folder] + "\\airport\\airport_directionality.csv"
    periods = RunMacro("Get Unconverged Periods", Args)
    
    dir_factors = RunMacro("Read Parameter File", {
        file: dir_factor_file,
        names: "period",
        values: "pa_factor"
    })
    
    for period in periods do
        pa_mtx_file = trips_dir + "/airport_pa_auto_trips_" + period + ".mtx"
        od_mtx_file = trips_dir + "/airport_auto_trips_" + period + ".mtx"
        CopyFile(pa_mtx_file, od_mtx_file)
        
        od_transpose_mtx_file = Substitute(od_mtx_file, ".mtx", "_transpose.mtx", )
        mat = OpenMatrix(od_mtx_file, )
        
        tmat = TransposeMatrix(mat, {
            {"File Name", od_transpose_mtx_file},
            {"Label", "Transposed Trips"},
            {"Type", "Double"}}
        )
        mat = null
        tmat = null
        
        mtx = CreateObject("Matrix", od_mtx_file)
        mtx_core_names = mtx.GetCoreNames()
        cores = mtx.GetCores()
        
        t_mtx = CreateObject("Matrix", od_transpose_mtx_file)
        t_cores = t_mtx.GetCores()
        
        pa_factor = dir_factors.(period)
          
        for core_name in mtx_core_names do    
            cores.(core_name) := Nz(cores.(core_name)) * pa_factor + Nz(t_cores.(core_name)) * (1 - pa_factor)
        end
        
        cores = null
        t_cores = null
        mtx = null
        t_mtx = null
        
        DeleteFile(od_transpose_mtx_file)
        DeleteFile(pa_mtx_file)
    end  
endmacro