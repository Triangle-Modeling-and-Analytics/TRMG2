Macro "Open PopEmpReached Dbox" (Args)
	RunDbox("PopEmpReached", Args)
endmacro

dBox "PopEmpReached" (Args) location: x, y
  Title: "Population_Employment_Accessibility Tool V 1.0" toolbox NoKeyBoard

  // What happens when the "x" is clicked
  close do
    return()
  enditem

  init do

    static x, y, TOD, Radius, TOD_Index, Radius_Index, Radius_list, TOD_list
	
    if x = null then x = -3
  
    EnableItem("Select time threshold(minutes)")
	  Radius_list = {"15", "30", "45", "60", "75", "90"}

	  EnableItem("Select TOD")
	  TOD_list = {"AM", "MD", "PM", "NT"}
	  
   enditem
  
  // Quit Button
  button 1, 15, 10 Prompt:"Quit" do
    Return(1)
  enditem
  
  Popdown Menu "Select time threshold(minutes)" 22,10,10,5 Prompt: "Select time threshold (minutes)" 
    List: Radius_list Variable: Radius_Index do
    Radius = Radius_list[Radius_Index]
  enditem
	
  Popdown Menu "Select TOD" 58,10,10,5 Prompt: "Choose TOD" 
    List: TOD_list Variable: TOD_Index do
    TOD = TOD_list[TOD_Index]
  enditem
  
  // Make Map Button
  button 40, 15, 30 Prompt:"Generate Results" do // button p1,p2,p3, p1 horizontal, p2 vertical, p3 length

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
  reporting_dir = scen_dir + "\\Output\\_reportingtool"
  //if GetDirectoryInfo(reporting_dir, "All") <> null then PutInRecycleBin(reporting_dir)
  output_dir = reporting_dir + "\\Pop_EmpReachedByHighwayTransit"
  temp_dir = output_dir + "\\Temp"
  RunMacro("Create Directory", output_dir)
  RunMacro("Create Directory", temp_dir)

  //Set parameter and file path
  auto_modes = {"sov", "hov"}
  tranist_accessmodes = {"w","pnr","knr"} 
  transit_modes = RunMacro("Get Transit Modes", TransModeTable) // get available transit mode in scenario
  
  // Get population and employment
  SE = CreateObject("df", se_file)
  TAZ_num = SE.nrow()
  SE.filter("Type = 'Internal'")
  SE.mutate("TotalPop", SE.tbl.HH_POP + SE.tbl.StudGQ_NCSU + SE.tbl.StudGQ_UNC + SE.tbl.StudGQ_DUKE + SE.tbl.StudGQ_NCCU)
  SE.select({"TAZ", "Type", "TotalPop", "TotalEmp"})
  TAZ_Emp = SE.get_col("TotalEmp")
  TAZ_Pop = SE.get_col("TotalPop")
  TotEmp = sum(V2A(nz(TAZ_Emp))) //need array
  TotPop = sum(V2A(nz(TAZ_Pop))) //need array
  
  // Porcess auto
  // Create a place holder for auto_skim result
  Auto_Skim_Mtx_Path = skim_dir + "\\roadway\\skim_sov_" + TOD +".mtx"
  Auto_Skim_Mtx_Handle = OpenMatrix(Auto_Skim_Mtx_Path,)
  Auto_Skim_Currency = CreateMatrixCurrency(Auto_Skim_Mtx_Handle, "CongTime", , , )
  tempmatfile = temp_dir + "/Auto_" + TOD + "_skim.mtx"
  matOpts = {"File Name": tempmatfile, Label: "Result MTX", Tables: {"Result"}}
  mOut = CopyMatrixStructure({Auto_Skim_Currency}, matOpts)
  mcOut = CreateMatrixCurrency(mOut,,,,)
  
  // Loop through auto skims
  for auto_mode in auto_modes do
    Auto_Skim_Mtx_Path = skim_dir + "\\roadway\\skim_" + auto_mode + "_" + TOD +".mtx"
    Auto_Skim_Mtx_Handle = OpenMatrix(Auto_Skim_Mtx_Path,)
    Auto_Skim_Currency = CreateMatrixCurrency(Auto_Skim_Mtx_Handle, "CongTime", , , )
    matrix_info = GetMatrixInfo(Auto_Skim_Mtx_Handle)

    //Fill new skim with 1 to keep only O-D pairs under time threshold
    mcOut = CreateMatrixCurrency(mOut,,,,)
    Opts = null
    Opts.Input.[Matrix Currency] = mcOut
    Opts.Global.Method = 11
    Opts.Global.[Cell Range] = 2
    Opts.Global.[Expression Text] = "if [Result]=1 then 1 else if [" + matrix_info[6].Label + "].[CongTime]<" + Radius + " then 1 else null"
    Opts.Global.[Force Missing] = "Yes"
    ret_value = RunMacro("TCB Run Operation", "Fill Matrices", Opts) 
  end

  skim_binfile = temp_dir + "/Auto_" + TOD + "_skim.bin"
  CreateTableFromMatrix(mOut, skim_binfile, "FFB", {{"Complete", "No"}, {"Tables", {"Result"}}})

  //Open skim bin and filter records based on time threshold
  //Aggregate by origin TAZ
  fields_to_sum = {"TotalPop", "TotalEmp"}
  dfa = null
  dfa = CreateObject("df", skim_binfile)
  dfa.left_join(SE, "Columns", "TAZ")
  dfa.filter("Type = 'Internal'")
  dfa.group_by("Rows")
  dfa.summarize(fields_to_sum, "sum")
  dfa.mutate("Pct_Pop_byAuto", dfa.tbl.sum_TotalPop/TotPop)
  dfa.mutate("Pct_Emp_byAuto", dfa.tbl.sum_TotalEmp/TotEmp)
  dfa.rename("sum_TotalPop", "Tot_Pop_byAuto")
  dfa.rename("sum_TotalEmp", "Tot_Emp_byAuto")
    
  // Porcess transit
  // Create a place holder for transit_skim result
  Transit_Skim_Mtx_Path = skim_dir + "\\transit\\skim_" + TOD +  "_w_lb.mtx"
  Transit_Skim_Mtx_Handle = OpenMatrix(Transit_Skim_Mtx_Path,)
  Transit_Skim_Currency = CreateMatrixCurrency(Transit_Skim_Mtx_Handle, "Total Time", , , )
  tempmatfile = temp_dir + "/transit_" + TOD + "_skim.mtx"
  matOpts = {"File Name": tempmatfile, Label: "Result MTX", Tables: {"Result"}}
  mOut = CopyMatrixStructure({Transit_Skim_Currency}, matOpts)
  mcOut = CreateMatrixCurrency(mOut,,,,)
  
  //Loop through transit skims
  for transit_mode in transit_modes do
    for access_mode in tranist_accessmodes do
        //Export Skim to Bin for easy manipulation
        Transit_Skim_Mtx_Path = skim_dir + "\\transit\\skim_" + TOD +  "_" + access_mode + "_" + transit_mode + ".mtx"
        Transit_Skim_Mtx_Handle = OpenMatrix(Transit_Skim_Mtx_Path,)
        Transit_Skim_Currency = CreateMatrixCurrency(Transit_Skim_Mtx_Handle, "Total Time", , , )
        matrix_info = GetMatrixInfo(Transit_Skim_Mtx_Handle)

        //Fill new skim with 1 to keep only O-D pairs under time threshold
        mcOut = CreateMatrixCurrency(mOut,,,,)
        Opts = null
        Opts.Input.[Matrix Currency] = mcOut
        Opts.Global.Method = 11
        Opts.Global.[Cell Range] = 2
        Opts.Global.[Expression Text] = "if [Result]=1 then 1 else if nz([" + matrix_info[6].Label + "].[Total Time])<" + Radius + " and nz([" + matrix_info[6].Label + "].[Total Time])>0 then 1 else null"
        Opts.Global.[Force Missing] = "Yes"
        ret_value = RunMacro("TCB Run Operation", "Fill Matrices", Opts) 
    end
  end
       
  skim_binfile = temp_dir + "/Transit_" + TOD + "_skim.bin"
  CreateTableFromMatrix(mOut, skim_binfile, "FFB", {{"Complete", "No"}, {"Tables", {"Result"}}})

  //Open skim bin and filter records based on time threshold
  //Aggregate by origin TAZ
  dft = null
  dft = CreateObject("df", skim_binfile)
  dft.left_join(SE, "Columns", "TAZ")
  dft.filter("Type = 'Internal'")
  dft.group_by("Rows")
  dft.summarize(fields_to_sum, "sum")
  dft.mutate("Pct_Pop_byTransit", dft.tbl.sum_TotalPop/TotPop)
  dft.mutate("Pct_Emp_byTransit", dft.tbl.sum_TotalEmp/TotEmp)
  dft.rename("sum_TotalPop", "Tot_Pop_byTransit")
  dft.rename("sum_TotalEmp", "Tot_Emp_byTransit")
  // because some TAZ have poor transit access even with pnr/knr so they cannot reach any destination within 15/30 minutes
  // by left join back to auto table, you have full list of TAZs.
  dfa.left_join(dft, "Rows", "Rows")
  dfa.rename("Rows", "TAZ") 
  dfa.write_csv(output_dir + "/PopEmpReachedin" + Radius + "Min_"+ TOD + ".csv") 
  RunMacro("Close All")
  PutInRecycleBin(temp_dir)
  Return(1)
endmacro