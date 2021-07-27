/*

*/

Macro "Airport" (Args)
    RunMacro("Airport Production", Args)
    RunMacro("Airport TOD", Args)	
	
    return(1)
endmacro

/*

*/

Macro "Airport Production" (Args)
    
	se_file = Args.SE
	skim_dir = Args.[Output Folder] + "\\skims\\roadway\\"
	airport_model_file = Args.[Input Folder] + "\\airport\\airport_model.csv"
	
	se_vw = OpenTable("se", "FFB", {se_file})
	
	data = GetDataVectors(
	    se_vw + "|",
		{
		    "TAZ", 
			"HH_POP",
			"Pct_Worker",
			"PctHighEarn",
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
	skim_mat = skim_dir + "skim_sov_MD.mtx"
	mat = CreateObject("Matrix")
	mat.LoadMatrix(skim_mat)
	cores = mat.data.cores
	distance_array = GetMatrixValues(cores.[Length (Skim)], V2A(taz_vec), {airport_zone})
	cores = null
	mat = null
	
	for i = 1 to distance_array.length do
	    dist_to_airport_miles = dist_to_airport_miles + {distance_array[i][1]}
	end
	
	dist_to_airport_miles = A2V(dist_to_airport_miles)
	
	// get variables for regression
	workers = data.HH_POP * data.Pct_Worker/100
	high_earners = workers * data.PctHighEarn/100
	high_earn_distance = high_earners * dist_to_airport_miles
	
	// read airport model file for coefficients
	coeffs = RunMacro("Read Parameter File", {
		file: airport_model_file,
		names: "variable",
		values: "coefficient"
	})
	
	// compute airport productions
	airport_productions = coeffs.intercept + 
		coeffs.employment * data.TotalEmp + 
		coeffs.high_earn_distance * high_earn_distance +
		coeffs.high_earner * high_earners
	
	airport_productions = if (airport_productions < 0) then 0 else airport_productions
	airport_productions = airport_productions * airport_enplanement / airport_productions.sum()
	
	a_fields = {{"AirportProd", "Real", 10, 2, , , , "airport productions"}}
	RunMacro("Add Fields", {view: se_vw, a_fields: a_fields})
	
	SetView(se_vw)
	SetDataVector(se_vw + "|", "AirportProd", airport_productions, )
	
	CloseView(se_vw)
endmacro

/*


*/

Macro "Airport TOD" (Args)
    
	se_file = Args.SE
	hwy_dbd = Args.Links
	trips_dir = Args.[Output Folder] + "\\airport\\"
	airport_tod_factor_file = Args.[Input Folder] + "\\airport\\airport_diurnals.csv"
	periods = Args.periods
	
	airport_matrix = trips_dir + "Airport_Trips.mtx"
	airport_transpose_matrix = trips_dir + "Airport_Transpose_Trips.mtx"
	
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
	
	obj = CreateObject("Matrix")
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

	// PA Trips
	rows = V2A(centroid_ids)
	cols = {airport_zone}
	for i = 1 to centroid_ids.length do 
	    pa_trips = pa_trips + {{airport_productions[i]}}
	end
	SetMatrixValues(mc, rows, cols, {"Copy", pa_trips}, )
	
	tmat = TransposeMatrix(mat, {
		{"File Name", airport_transpose_matrix},
		{"Label", "Airport Transposed Trips"}, 
		{"Type", "Double"}}
	)
	
	mc = null
	mat = null
	tmat = null
	CloseView(se_vw)
	CloseMap(map)
	
	mat = CreateObject("Matrix")
	mat.LoadMatrix(airport_matrix)
	tmat = CreateObject("Matrix")
	tmat.LoadMatrix(airport_transpose_matrix)
	
	fac_vw = OpenTable("tod_fac", "CSV", {airport_tod_factor_file})
	v_pa_fac = GetDataVector(fac_vw + "|", "PA_Factor", )
	v_ap_fac = GetDataVector(fac_vw + "|", "AP_Factor", )
	
	for p = 1 to periods.length do 
	    period = periods[p]
		pa_factor = v_pa_fac[p]
		ap_factor = v_ap_fac[p]
	    
		mat.AddCores({"Trips_" + period})
		cores = mat.data.cores
		tcores = tmat.data.cores
		cores.("Trips_" + period) := Nz(cores.Trips) * pa_factor + Nz(tcores.Trips) * ap_factor
	end
	
	CloseView(fac_vw)
	mat.DropCores({"Trips"})
	tmat = null
	tcores = null
	DeleteFile(airport_transpose_matrix)
endmacro
