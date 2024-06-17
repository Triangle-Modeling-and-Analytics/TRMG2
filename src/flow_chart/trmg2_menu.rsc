
Class "Visualize.Menu.Items"

    init do 
        self.runtimeObj = CreateObject("Model.Runtime")
    enditem 

    Macro "GetMenus" do
        Menus = {
             { ID: "ConvChart", Title: "Convergence Chart" , Macro: "Menu_ConvergenceChart" }
            ,{ ID: "FlowMap", Title: "Flow Map" , Macro: "Menu_FlowMapt" }
            ,{ ID: "M_Chord", Title: "Chord Diagram" , Macro: "Menu_Chord" }
            ,{ ID: "M_Sankey", Title: "Sankey Diagram" , Macro: "Menu_Sankey" }
            }
        
        Return(Menus)
    enditem 

    Macro "Menu_FlowMapt" do 
        opts.tableArg = self.runtimeObj.GetSelectedParamInfo().Value
        opts.FlowFields = {"AB_Flow","BA_Flow"}
        opts.vocFields = {"AB_VOC","BA_VOC"}
        opts.LineLayer = self.runtimeObj.GetValue("HWYDB")
        self.runtimeObj.RunCode("CreateFlowThemes", opts)
        enditem 

    Macro "Menu_ConvergenceChart" do 
        tableArg = self.runtimeObj.GetSelectedParamInfo().Value
        self.runtimeObj.RunCode("ConvergenceChart", {TableName: tableArg})
        enditem 

    macro "Menu_Chord" do 
        mName = self.runtimeObj.GetSelectedParamInfo().Value
        TAZGeoFile = self.runtimeObj.GetValue("TG_ZonalTable")
        self.runtimeObj.RunCode("CreateWebDiagram", {MatrixName: mName, TAZDB: TAZGeoFile, DiagramType: "Chord"})
    enditem         

    macro "Menu_Sankey" do 
        mName = self.runtimeObj.GetSelectedParamInfo().Value
        TAZGeoFile = self.runtimeObj.GetValue("TG_ZonalTable")
        self.runtimeObj.RunCode("CreateWebDiagram", {MatrixName: mName, TAZDB: TAZGeoFile, DiagramType: "Sankey"})
    enditem         

EndClass


MenuItem "TRMG2 Menu Item" text: "TRMG2"
    menu "TRMG2 Menu"

menu "TRMG2 Menu"
    init do
    enditem

    MenuItem "Create Scenario" text: "Create Scenario"
        do 
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        {, scen_name} = mr.GetScenario()

        // Check that a scenario is selected and that a folder has been chosen
        if scen_name = null then do
            ShowMessage("Choose a scenario.")
            return()
        end
        if Args.[Scenario Folder] = null then do
            ShowMessage(
                "Choose a folder for the current scenario\n" +
                "(Parameters -> Files -> Scenario -> Input)"
            )
            return()
        end

        // Check if anything has already been created in the scenario directory
        dir = Args.[Input Folder] + "/*"
        if GetDirectoryInfo(dir, "All") <> null then do
            opts = null
            opts.Buttons = "YesNo"
            opts.Caption = "Note"
            str = "The input folder already contains information.\n" +
            "Continuing will overwrite any manual changes made.\n" +
            "(The output folder will not be modified.)\n" +
            "Are you sure you want to continue?"
            yesno = MessageBox(str, opts)
        end
        if yesno = "Yes" or yesno = null then do
            mr.RunCode("Create Scenario", Args)
            ShowMessage("Scenario Created")
        end
        return(1)
    enditem

    separator

    MenuItem "Utils" text: "Tools"
        menu "TRMG2 Utilities"
    
    MenuItem "Calibrators" text: "Calibrators"
        menu "TRMG2 Calibrators"
endMenu 
menu "TRMG2 Utilities"
    init do
    enditem

    MenuItem "Highway" text: "Highway Analysis"
        menu "Highway Analysis"
    
    MenuItem "Accessibility" text: "Accessibility Analysis"
        menu "Accessibility Analysis"

    MenuItem "Matrix" text: "Matrix Aggregation"
        menu "Matrix Aggregation"

    MenuItem "Comparison" text: "Scenario Comparison"
        menu "Scenario Comparison"
    
    MenuItem "Input" text: "Input Data Processing"
        menu "Input Data Processing"

    MenuItem "Performance" text: "Performance Measures"
        menu "Performance Measures"
    
    MenuItem "FManagement" text: "File Management"
        menu "File Management"

    MenuItem "TIA" text: "TIA Site Analysis"
        menu "TIA Site Analysis"
    
endMenu

menu "Highway Analysis"
    init do
    enditem
    
    MenuItem "desire_lines" text: "Desire Lines" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Open Desire Lines Dbox", Args)
    enditem

    MenuItem "fixed_od" text: "Fixed OD Assignment" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Open Fixed OD Dbox", Args)
    enditem

    MenuItem "fixed_od_multi" text: "FixedOD Multiple Projects" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Open FixedOD Multiple Projects Dbox", Args)
    enditem

endMenu

menu "Accessibility Analysis"
    init do
    enditem

    MenuItem "PopEmpReached" text: "Population and Employement Accessibility" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Open PopEmpReached Dbox", Args)
    enditem
	
	MenuItem "TRMTransitCoverage_Poverty" text: "Transit Poverty HH Coverage" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Open Transit Poverty HH Coverage Dbox", Args)
    enditem

    MenuItem "TRMTransitCoverage_HHStrata" text: "Transit HH Strata Coverage" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Open Transit HH Strata Coverage Dbox", Args)
    enditem
endMenu

menu "Matrix Aggregation"
    init do
    enditem
    
    MenuItem "TripAggregation_Moto" text: "Motorized Trip Matrix Aggregation" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Open Moto Trip Aggregation Tool Dbox", Args)
    enditem

    MenuItem "TripAggregation_NM" text: "NM Trip Matrix Aggregation" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Open NM Trip Aggregation Tool Dbox", Args)
    enditem

    MenuItem "TripAggregation_Daily" text: "Daily Matrix Creation" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Open Daily Matrix Creation Tool Dbox", Args)
    enditem

endMenu

menu "Scenario Comparison"
    init do
    enditem

    MenuItem "TransitScenarioComparion" text: "Transit Scenario Comparison" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Open Transit Scenario Comparison Dbox", Args)
    enditem
    
    MenuItem "ZonalVMT" text: "Zonal VMT Calculation" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Open Zonal VMT Calculation Dbox", Args)
    enditem
  
    MenuItem "scen comp" text: "Scenario Comparison" do
        mr = CreateObject("Model.Runtime")
        mr.RunCodeEx("Open Scenario Comp Tool")
    enditem
endMenu

menu "Input Data Processing"
    init do
    enditem

    MenuItem "diff" text: "Diff Tool" do
        mr = CreateObject("Model.Runtime")
        mr.RunCodeEx("Open Diff Tool")
    enditem

    MenuItem "merge_tool" text: "Merge Line Layers" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCodeEx("Open Merge Dbox", Args)
    enditem

    MenuItem "seupdate_tool" text: "Update SE Data" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCodeEx("Open SEUpdate Dbox", Args)
    enditem
endMenu

menu "Performance Measures"
    init do
    enditem

    MenuItem "MOVES" text: "MOVES Input Preparation" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Open Prepare MOVES Input Dbox", Args)
    enditem
    
    MenuItem "Concatenate Files" text: "Concatenate CSV Files" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Open Concatenate Files Dbox", Args)
    enditem

endMenu

menu "File Management"
    init do
    enditem

    MenuItem "Delete Files Tool" text: "Delete Files" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Open Delete Files Tool Dbox", Args)
    enditem

endMenu

menu "TIA Site Analysis"
    init do
    enditem

    MenuItem "Zone" text: "Zone VMT Metrics" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Open TIA Zone VMT Dbox", Args)
    enditem

    MenuItem "Link" text: "Link VMT Metric"
        menu "Link VMT Metric"
endMenu

menu "TRMG2 Calibrators"
    init do
    enditem

    MenuItem "AO" text: "Auto Ownership" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Calibrate AO", Args)
    enditem

    MenuItem "NM" text: "Nonmotorized" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Calibrate NM", Args)
    enditem

    MenuItem "HB Mode Choice" text: "Home Based Trips Mode Choice" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Calibrate HB MC", Args)
    enditem
endMenu

menu "Link VMT Metric"
    init do
    enditem

    MenuItem "SL" text: "Select Link Analysis" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Open Select Link Dbox", Args)
    enditem

    MenuItem "LinkVMT" text: "Calculate Link VMT" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Open TIA Link VMT Dbox", Args)
    enditem
endMenu


