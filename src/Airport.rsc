/*

*/

Macro "Airport" (Args)
    RunMacro("Airport Production", Args)
    RunMacro("Airport TOD", Args)	
	
    return(1)
endmacro

/*
Regression model for airport production: 
(4.3687 + 0.0254 * employment - 0.0034 * high_earn_distance + 0.1880 * high_earners)
*/

Macro "Airport Production" (Args)
    
	se_file = Args.SE
	skim_dir = Args.[Output Folder] + "\\skims\\roadway\\"
	
	AIRPORT_ENPLANEMENTS = 45000		// TODO-AK: get this from flowchart parameter
	AIRPORT_ZONE = 2369                 // TODO-AK: get this from flowchart parameter
	
	// TODO-AK: delete the hard-coded paths (used for testing)
	se_file = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\sedata\\scenario_se.bin"
	skim_dir = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\skims\\roadway\\"
	
	se_vw = OpenTable("se", "FFB", {se_file})
	
	data = GetDataVectors(
	    se_vw + "|",
		{
		    "TAZ", 
			"HH_POP",
			"Pct_Worker",
			"PctHighEarn",
		    "Industry",
			"Office", 
			"Service_RateLow",
			"Service_RateHigh",
			"Retail"
		},
		{OptArray: TRUE}
	)
	
	taz_vec = data.TAZ
	
	skim_mat = skim_dir + "skim_sov_MD.mtx"
	mat = CreateObject("Matrix")
	mat.LoadMatrix(skim_mat)
	cores = mat.data.cores
	distance_array = GetMatrixValues(cores.[Length (Skim)], V2A(taz_vec), {AIRPORT_ZONE})
	cores = null
	mat = null
	
	for i = 1 to distance_array.length do
	    dist_to_airport_miles = dist_to_airport_miles + {distance_array[i][1]}
	end
	
	dist_to_airport_miles = A2V(dist_to_airport_miles)
	
	tot_emp = data.Industry + data.Office + data.Service_RateLow + data.Service_RateHigh + data.Retail
	workers = data.HH_POP * data.Pct_Worker/100
	high_earners = workers * data.PctHighEarn/100
	high_earn_distance = high_earners * dist_to_airport_miles
	
	//TODO-AK: Ask Kyle on how he prefers the coefficient saved/read
	airport_productions = 4.3687 + (0.0254 * tot_emp) - (0.0034 * high_earn_distance) + (0.1880 * high_earners)
	airport_productions = if (airport_productions < 0) then 0 else airport_productions
	airport_productions = airport_productions * AIRPORT_ENPLANEMENTS / airport_productions.sum()
	
	a_fields = {
        {"AirportProd", "Real", 10, 2, , , , "airport productions"}
    }
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
	trips_dir = Args.[Output Folder] + "\\assignment\\"		// TODO-AK: change the trips dir to where the trip matrices will be stored. 
	airport_tod_factor_file = Args.[Output Folder]			// TODO-AK: change the dir to parameters (airport tod factors)
	periods = Args.periods
	
	AIRPORT_ZONE = 2369                                     // TODO-AK: get this from flowchart parameter
		
	// TODO-AK: delete these hard-coded paths (used for testing)
	se_file = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\sedata\\scenario_se.bin"
	hwy_dbd = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\networks\\scenario_links.dbd"
	trips_dir = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\assignment\\"
	airport_tod_factor_file = "D:\\Models\\TRMG2\\master\\airport\\airport_diurnals.csv"
	periods = {"AM", "MD", "PM", "NT"}
	
	airport_matrix = trips_dir + "Airport_Trips.mtx"
	airport_transpose_matrix = trips_dir + "Airport_Transpose_Trips.mtx"
	
	se_vw = OpenTable("se", "FFB", {se_file})

	SetView(se_vw)
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

	// P2A Trips
	rows = V2A(centroid_ids)
	cols = {AIRPORT_ZONE}
	for i = 1 to centroid_ids.length do 
	    pa_trips = pa_trips + {{airport_productions[i]}}
	end
	SetMatrixValues(mc, rows, cols, {"Copy", pa_trips}, )
	
	// A2P Trips
	rows = V2A(centroid_ids)
	cols = {AIRPORT_ZONE}
	for i = 1 to centroid_ids.length do 
	    ap_trips = ap_trips + {{airport_productions[i]}}
	end
	SetMatrixValues(mc, rows, cols, {"Add", ap_trips}, )
	
	tmat = TransposeMatrix(mat, {{"File Name", airport_transpose_matrix},{"Label", "Airport Transposed Trips"}, {"Type", "Double"}})
	
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
	
	cores = null
	tcores = null
	mat = null
	tmat = null
	CloseView(fac_vw)
	
	DeleteFile(airport_transpose_matrix)
	
endmacro
