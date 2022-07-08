Macro "Open PopEmpReached Dbox" (Args)
	RunDbox("PopEmpReached", Args)
endmacro

dBox "PopEmpReached" (Args) center, center, 60, 9
  Title: "Population_Employment_Accessibility Tool V 1.0" toolbox NoKeyBoard

  // What happens when the "x" is clicked
  close do
    return()
  enditem

  init do

    static TOD, Radius, TOD_Index, Radius_Index, Radius_list, TOD_list
	
    EnableItem("Select time threshold(minutes)")
	  Radius_list = {"15", "30", "45", "60", "75", "90"}

	  EnableItem("Select TOD")
	  TOD_list = {"AM", "MD", "PM", "NT"}
	  
   enditem
  
  // Quit Button
  button 5, 7, 10 Prompt:"Quit" do
    Return(1)
  enditem
  
  Popdown Menu "Select time threshold(minutes)" 30,1,10,5 Prompt: "Select time threshold (minutes)" 
    List: Radius_list Variable: Radius_Index do
    Radius = Radius_list[Radius_Index]
  enditem
	
  Popdown Menu "Select TOD" 14,4,10,5 Prompt: "Choose TOD" 
    List: TOD_list Variable: TOD_Index do
    TOD = TOD_list[TOD_Index]
  enditem
  
  // Make Map Button
  button 25, 7, 30 Prompt:"Generate Results" do // button p1,p2,p3, p1 horizontal, p2 vertical, p3 length

    if !RunMacro("Highway_Transit_PopEmp", Args, Radius, TOD) then goto exit	

 
    ShowMessage("Reports have been created successfully.")
	return(1)
	
	
    exit:	
    showmessage("Something is wrong")	
    return(0)
  Enditem
Enddbox

//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                        Macro "Highway_Transit_PopEmp"
//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Macro "Highway_Transit_PopEmp" (Args, Radius, TOD) 
  // Set working directory
  RunMacro("TCB Init")
  scen_dir = Args.[Scenario Folder]
  skim_dir = scen_dir + "\\Output\\skims"
  se_file = scen_dir + "\\Output\\sedata\\scenario_se.bin"
  TransModeTable = Args.TransModeTable
  reporting_dir = scen_dir + "\\Output\\_summaries"
  //if GetDirectoryInfo(reporting_dir, "All") <> null then PutInRecycleBin(reporting_dir)
  output_dir = reporting_dir + "\\Pop_Emp_Accessibility"
  temp_dir = output_dir + "\\Temp"
  RunMacro("Create Directory", output_dir)
  RunMacro("Create Directory", temp_dir)

  //Set parameter and file path
  auto_modes = {"sov", "hov"}
  tranist_accessmodes = Args.access_modes
  transit_modes = RunMacro("Get Transit Modes", TransModeTable) // get available transit mode in scenario
  
  // Get population and employment
  SE = CreateObject("df", se_file)
  //SE.filter("Type = 'Internal'")
  SE.mutate("TotalPop", SE.tbl.HH_POP + SE.tbl.StudGQ_NCSU + SE.tbl.StudGQ_UNC + SE.tbl.StudGQ_DUKE + SE.tbl.StudGQ_NCCU)
  SE.select({"TAZ", "Type", "TotalPop", "TotalEmp"})
  TAZ_Emp = SE.get_col("TotalEmp")
  TAZ_Pop = SE.get_col("TotalPop")
  TotEmp = sum(V2A(nz(TAZ_Emp))) //need array
  TotPop = sum(V2A(nz(TAZ_Pop))) //need array
  
  // Create a place holder for auto_skim result
  se_vw = OpenTable("se", "FFB", {se_file})
  mtx_file = temp_dir + "/Auto_" + TOD + "_skim.mtx"
  mh = CreateMatrixFromView("temp", se_vw + "|", "TAZ", "TAZ", {"TAZ"}, {"File Name": mtx_file})
  mtx = CreateObject("Matrix", mh)
  CloseView(se_vw)
  mtx.AddCores({"Auto_Result"})
  mtx.DropCores({"TAZ"})

  // Loop through auto skims
  for auto_mode in auto_modes do
    auto_skim_mtx_path = skim_dir + "\\roadway\\skim_" + auto_mode + "_" + TOD +".mtx"
    auto_skim_mtx = CreateObject("Matrix", auto_skim_mtx_path)
    auto_skinm_core = auto_skim_mtx.GetCore("CongTime")

    //Fill new skim with 1 to keep only O-D pairs under time threshold
    mc = mtx.GetCore("Auto_Result")
    mc := if mc = 1 then 1 else if nz(auto_skinm_core) < s2r(Radius) and nz(auto_skinm_core) then 1 else null
  end

  automatrix = OpenMatrix(mtx_file,)  
  autoskim_binfile = temp_dir + "/Auto_" + TOD + "_skim.bin"
  CreateTableFromMatrix(automatrix, autoskim_binfile, "FFB", {{"Complete", "No"}, {"Tables", {"Auto_Result"}}})
 
  // Porcess transit
  // Create a place holder for transit_skim result
  se_vw = OpenTable("se", "FFB", {se_file})
  mtx_file = temp_dir + "/Transit_" + TOD + "_skim.mtx"
  mh = CreateMatrixFromView("temp", se_vw + "|", "TAZ", "TAZ", {"TAZ"}, {"File Name": mtx_file})
  mtx = CreateObject("Matrix", mh)
  CloseView(se_vw)
  mtx.AddCores({"Transit_Result"})
  mtx.DropCores({"TAZ"})

  //Loop through transit skims
  for transit_mode in transit_modes do
    for access_mode in tranist_accessmodes do
        transit_skim_mtx_path = skim_dir + "\\transit\\skim_" + TOD +  "_" + access_mode + "_" + transit_mode + ".mtx"
        transit_skim_mtx = CreateObject("Matrix", transit_skim_mtx_path)
        transit_skim_core = transit_skim_mtx.GetCore("Total Time")

        //Fill new skim with 1 to keep only O-D pairs under time threshold
        mc = mtx.GetCore("Transit_Result")
        mc := if mc = 1 then 1 else if nz(transit_skim_core) < s2r(Radius) and nz(transit_skim_core) >0 then 1 else null
    end
  end

  transitmatrix = OpenMatrix(mtx_file,)  
  transitskim_binfile = temp_dir + "/Transit_" + TOD + "_skim.bin"
  CreateTableFromMatrix(transitmatrix, transitskim_binfile, "FFB", {{"Complete", "No"}, {"Tables", {"Transit_Result"}}})
  
  // Close mtx
  mh = null
  mtx = null  
  mc = null
  auto_skim_mtx = null
  auto_skinm_core = null
  transit_skim_mtx = null
  transit_skim_core = null
  automatrix = null
  transitmatrix = null

  //Open skim bin and filter records based on time threshold
  //Aggregate by origin TAZ
  fields_to_sum = {"TotalPop", "TotalEmp"}
  dfa = null
  dfa = CreateObject("df", autoskim_binfile)
  names = dfa.colnames()
  dfa.rename(names[1], "Row")
  dfa.rename(names[2], "Col")
  dfa.left_join(SE, "Col", "TAZ")
  //dfa.filter("Type = 'Internal'")
  dfa.group_by("Row")
  dfa.summarize(fields_to_sum, "sum")
  dfa.mutate("Pct_Pop_byAuto", dfa.tbl.sum_TotalPop/TotPop)
  dfa.mutate("Pct_Emp_byAuto", dfa.tbl.sum_TotalEmp/TotEmp)
  dfa.rename("sum_TotalPop", "Tot_Pop_byAuto")
  dfa.rename("sum_TotalEmp", "Tot_Emp_byAuto")

  //Open skim bin and filter records based on time threshold
  //Aggregate by origin TAZ
  dft = null
  dft = CreateObject("df", transitskim_binfile)
  names = dft.colnames()
  dft.rename(names[1], "Row")
  dft.rename(names[2], "Col")
  dft.left_join(SE, "Col", "TAZ")
  //dft.filter("Type = 'Internal'")
  dft.group_by("Row")
  dft.summarize(fields_to_sum, "sum")
  dft.mutate("Pct_Pop_byTransit", dft.tbl.sum_TotalPop/TotPop)
  dft.mutate("Pct_Emp_byTransit", dft.tbl.sum_TotalEmp/TotEmp)
  dft.rename("sum_TotalPop", "Tot_Pop_byTransit")
  dft.rename("sum_TotalEmp", "Tot_Emp_byTransit")

  // because some TAZ have poor transit access even with pnr/knr so they cannot reach any destination within 15/30 minutes
  // by left join back to auto table, you have full list of TAZs.
  dfa.left_join(dft, "Row", "Row")
  dfa.rename("Row", "TAZ")
  dfa.write_csv(output_dir + "/PopEmpReachedin" + Radius + "Min_"+ TOD + ".csv") 
  
  RunMacro("Close All")

  //Delete temp files
  files = GetDirectoryInfo(temp_dir + "/*", "File")
  for i = 1 to files.length do
    file = files[i][1]
    filepath = temp_dir + "/" + file
    DeleteFile(filepath)
  end
  RemoveDirectory(temp_dir)

  Return(1)
endmacro