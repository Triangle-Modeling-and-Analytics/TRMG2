Macro "Export"
    RunMacro("Export Scenario Bin to CSV")
    RunMacro("Export University Trip Matrices")  
	RunMacro("Export Skim Matrix")
	ShowMessage("done")
EndMacro

Macro "Export Scenario Bin to CSV"
    se_bin_file = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\sedata\\scenario_se.bin"
    se_csv_file = "D:\\Models\\TRMG2\\docs\\data\\output\\university\\university_model_summaries\\data\\interim\\scenario_se.csv"
    se_dcc_file = Substitute(se_csv_file, ".csv", ".dcc", )
	if GetFileInfo(se_csv_file) <> null then DeleteFile(se_csv_file)
	
    se_vw = OpenTable("se", "FFB", {se_bin_file})
    
    ExportView(se_vw + "|", "CSV", se_csv_file, , {"CSV Header": "true"})
   
    CloseView(se_vw)
	
	if GetFileInfo(se_dcc_file) <> null then DeleteFile(se_dcc_file)
EndMacro

Macro "Export University Trip Matrices"
    periods = {"AM", "MD", "PM", "NT"}
    mtx_file_path = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\university\\"
    csv_file_path = "D:\\Models\\TRMG2\\docs\\data\\output\\university\\university_model_summaries\\data\\interim\\"
    
	// ALL TRIPS
    for period in periods do
        mtx_file = mtx_file_path + "university_trips_" + period + ".mtx"
		
		mtx = OpenMatrix(mtx_file, )
		
	    csv_file = csv_file_path + "university_trips_" + period + ".csv"
	    
		if GetFileInfo(csv_file) <> null then DeleteFile(csv_file)
		
	    CreateTableFromMatrix(mtx, csv_file, "CSV", {{"Complete", "Yes"}, {"Tables", {"auto", "transit", "walk", "bike"}}})
   
        mtx = null
		
		dcc_file = Substitute(csv_file, ".csv", ".dcc", )
		if GetFileInfo(dcc_file) <> null then DeleteFile(dcc_file)
    end
	
	// UHC_OFF CAMPUS
	for period in periods do 
	    mtx_file = mtx_file_path + "university_mode_trips_UHC_OFF_" + period + ".mtx"
		mtx = OpenMatrix(mtx_file, )
		
		csv_file = csv_file_path + "university_mode_trips_UHC_OFF_" + period + ".csv"
		
		if GetFileInfo(csv_file) <> null then DeleteFile(csv_file)
		
		CreateTableFromMatrix(mtx, csv_file, "CSV", {{"Complete", "Yes"}, {"Tables", {"auto", "transit", "walk", "bike"}}})
		
		mtx = null
		
		dcc_file = Substitute(csv_file, ".csv", ".dcc", )
		if GetFileInfo(dcc_file) <> null then DeleteFile(dcc_file)
	end
   
EndMacro

Macro "Export Skim Matrix"
    mtx_file_path = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\skims\\roadway\\"
    csv_file_path = "D:\\Models\\TRMG2\\docs\\data\\output\\university\\university_model_summaries\\data\\interim\\"

    mtx_file = mtx_file_path + "skim_sov_AM.mtx"
	
	mtx = OpenMatrix(mtx_file, )
	
	csv_file = csv_file_path + "sov_distance_skim_am.csv"
	
	if GetFileInfo(csv_file) <> null then DeleteFile(csv_file)
	
	CreateTableFromMatrix(mtx, csv_file, "CSV", {{"Complete", "Yes"}, {"Tables", {"Length (Skim)"}}})
   
    mtx = null
	
	dcc_file = Substitute(csv_file, ".csv", ".dcc", )
	if GetFileInfo(dcc_file) <> null then DeleteFile(dcc_file)
EndMacro
