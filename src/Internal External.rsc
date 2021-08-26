/*

*/

Macro "Internal External" (Args)
    RunMacro("External", Args)
	
    return(1)
endmacro

/*
EE Model
*/

Macro "External" (Args)
    RunMacro("TCB Init")
	RunMacro("Convert EE CSV to MTX", Args)
	RunMacro("Calculate EE IPF Marginals", Args)
	RunMacro("IPF EE Seed Table", Args)
	RunMacro("EE Symmetry", Args)
	ShowMessage("done")
endmacro

/*
Convert the base ee seed csv to mtx.
The matrix is created based on the external stations in the node layer
*/

Macro "Convert EE CSV to MTX" (Args)
    //hwy_dbd = Args.Links
	//ee_csv_file = Args.[Input Folder] + "\\external\\ee-seed.csv"
	//ee_mtx_file = Args.[Output Folder] + "\\external\\base_ee_table.mtx
	
	// TODO-AK: delete the hard-coded paths (used for testing)
	hwy_dbd = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\networks\\scenario_links.dbd"
	ee_csv_file = "D:\\Models\\TRMG2\\scenarios\\base_2016\\input\\external\\ee-seed.csv"
	ee_mtx_file = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\external\\base_ee_table.mtx"
	
	// create empty EE matrix from node layer
	{map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd})
	
    SetLayer(nlyr)
	qry = "Select * where External = 1"
	n = SelectByQuery("ext", "Several", qry)
    if n = 0 then Throw("No external stations found")
	
	opts = null
	opts.[File Name] = ee_mtx_file
	opts.Label = "EE Matrix"
	opts.Tables = {"trips_auto", "trips_cv_sut", "trips_cv_mut"}
	row_spec = {nlyr + "|ext", nlyr + ".ID", "externals"}
	
	mtx = CreateMatrix(row_spec, , opts)
    
	// update the EE matrix with the seed csv
	view = OpenTable("csv", "CSV", {ee_csv_file})
	opts = null
	opts.[Missing Is Zero] = "Yes"
	UpdateMatrixFromView(
	  mtx,
	  view + "|",
	  "orig_taz",
	  "dest_taz",
	  null,
	  {view + ".auto", view + ".cv_sut", view + ".cv_mut"},
	  "Replace",
	  opts
	)
	
	mtx = null
	CloseView(view)
	CloseMap(map)
endmacro 


/*
Calculate the production and attraction marginals at each external station. 
*/

Macro "Calculate EE IPF Marginals" (Args)
  //se_file = Args.SE
  
  // TODO-AK: delete the hard-coded paths (used for testing)
  se_file = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\sedata\\scenario_se.bin"
  
  se_vw = OpenTable("se", "FFB", {se_file})
  SetView(se_vw)

  data = GetDataVectors(
    se_vw + "|",
  	{
	  "TAZ", 
  	  "PCTAUTOEE",
  	  "PCTCV",
	  "PCTCVSUTEE",
	  "PCTCVMUTEE",
  	  "ADT"
  	},
  	{OptArray: TRUE}
  )
  
  // TODO-AK: confirm the PCTs are used correctly for ADT split
  ee_auto_marg = Nz(data.PCTAUTOEE)/100 * (1 - Nz(data.PCTCV)/100) * Nz(data.ADT) / 2
  ee_cv_sut_marg = Nz(data.PCTAUTOEE)/100 * Nz(data.PCTCVSUTEE)/100 * Nz(data.ADT) / 2
  ee_cv_mut_marg = Nz(data.PCTAUTOEE)/100 * Nz(data.PCTCVMUTEE)/100 * Nz(data.ADT) / 2
  
  a_fields = {
    {"EE_AUTO_MARG", "Real", 10, 2, , , , "ee auto marginal"},
	{"EE_CV_SUT_MARG", "Real", 10, 2, , , , "ee cv sut marginal"},
	{"EE_CV_MUT_MARG", "Real", 10, 2, , , , "ee cv mut marginal"}
  }
  
  RunMacro("Add Fields", {view: se_vw, a_fields: a_fields})
  
  SetView(se_vw)
  SetDataVector(se_vw + "|", "EE_AUTO_MARG", ee_auto_marg, )
  SetDataVector(se_vw + "|", "EE_CV_SUT_MARG", ee_cv_sut_marg, )
  SetDataVector(se_vw + "|", "EE_CV_MUT_MARG", ee_cv_mut_marg, )
  
  CloseView(se_vw)
	
endmacro


/*
Use the calculated marginals to IPF the base-year ee matrix.
*/

Macro "IPF EE Seed Table" (Args)
  //base_mtx_file = Args.[Output Folder] + "\\external\\base_ee_table.mtx
  //ee_mtx_file = Args.[Output Folder] + "\\external\\ee_trips.mtx
  //se_file = Args.SE
  
  // TODO-AK: delete the hard-coded paths (used for testing)
  base_mtx_file = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\external\\base_ee_table.mtx"
  ee_mtx_file = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\external\\ee_trips.mtx"
  se_file = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\sedata\\scenario_se.bin"
  
  mtx = OpenMatrix(base_mtx_file, )
  core_names = GetMatrixCoreNames(mtx)
  {ri, ci} = GetMatrixIndex(mtx)
  
  // IPF EE trips
  Opts = null
  Opts.Input.[Base Matrix Currency] = {base_mtx_file, core_names[1], ri, ci}
  Opts.Input.[PA View Set] = {se_file, "se", "ext", "Select * where Type = 'External'"}
  Opts.Global.[Constraint Type] = "Doubly"
  Opts.Global.Iterations = 300
  Opts.Global.Convergence = 0.001
  Opts.Field.[Core Names Used] = core_names
  Opts.Field.[P Core Fields] = {"se.EE_AUTO_MARG", "se.EE_CV_SUT_MARG", "se.EE_CV_MUT_MARG"}
  Opts.Field.[A Core Fields] = {"se.EE_AUTO_MARG", "se.EE_CV_SUT_MARG", "se.EE_CV_MUT_MARG"}
  Opts.Output.[Output Matrix].Label = "EE Trips Matrix"
  Opts.Output.[Output Matrix].[File Name] = ee_mtx_file
  ok = RunMacro("TCB Run Procedure", "Growth Factor", Opts, &Ret)
  
  if !ok then Throw("EE IPF failed")
  
  // Check each core for errors not captured automatically by TC
  for c = 1 to Opts.Field.[Core Names Used].length do
    // e.g., if the "Fail0" option in the second element of the
    // Ret array is greater than zero, it failed
    if Ret[2].("Fail" + String(c-1)) > 0 then do
      errorcore = Opts.Field.[Core Names Used][c]
      Throw(
        "EE IPF failed. Core: " + errorcore
        )
    end
  end
  
endmacro

/*
This macro enforces symmetry on the EE matrix.
*/

Macro "EE Symmetry"
  //ee_mtx_file = Args.[Output Folder] + "\\external\\ee_trips.mtx
  
  //TODO-AK: Delete hard-coded file path
  ee_mtx_file = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\external\\ee_trips.mtx"
  
  // Open the IPFd EE mtx
  mtx = OpenMatrix(ee_mtx_file, )
  a_corenames = GetMatrixCoreNames(mtx)
  {ri, ci} = GetMatrixIndex(mtx)
  Cur = CreateMatrixCurrencies(mtx, ri, ci, )

  // Create a transposed EE matrix
  tmtx = GetTempFileName(".mtx")
  opts = null
  opts.[File Name] = tmtx
  opts.Label = transposed
  tmtx = TransposeMatrix(mtx, opts)

  // Create transposed currencies
  {tri, tci} = GetMatrixIndex(tmtx)
  tcur = CreateMatrixCurrencies(tmtx, tri, tci, )

  a_corename = GetMatrixCoreNames(mtx)
  for c = 1 to a_corename.length do
    corename = a_corename[c]
	
	// Add together and divide by two to ensure symmetry
    Cur.(corename) := (Cur.(corename) + tcur.(corename))/2
  end
EndMacro