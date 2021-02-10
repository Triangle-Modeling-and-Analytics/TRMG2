/*
Handle initial steps like capacity and speed calculations.
*/

Macro "Initial Processing" (Args)
  
  RunMacro("Create Output Copies", Args)
  // RunMacro("Determine Area Type", Args)
  // RunMacro("Capacity", Args)
  // RunMacro("Set CC Speeds", Args)
  // RunMacro("Other Attributes", Args)
  // RunMacro("Filter Transit Settings", Args)

  return(1)
EndMacro

/*
Creates copies of the scenario/input SE, TAZs, and networks.
The model will modify the output copy, leaving
the input files as they were.  This helps when looking back at
older scenarios.
*/

Macro "Create Output Copies" (Args)

  opts = null
  opts.from_rts = Args.[Input Routes]
  {drive, folder, filename, ext} = SplitPath(Args.Routes)
  opts.to_dir = drive + folder
  opts.include_hwy_files = "true"
  RunMacro("Copy RTS Files", opts)
  CopyDatabase(Args.[Input TAZs], Args.TAZs)
  se = OpenTable("se", "FFB", {Args.[Input SE]})
  ExportView(se + "|", "FFB", Args.SE, , )
  CloseView(se)
EndMacro