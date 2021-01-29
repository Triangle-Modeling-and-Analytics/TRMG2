/*
    * Macro that performs population synthesis using the TransCAD (9.0) built-in procedure. 
        * Marginal Data - Disaggregated SED Marginals (by TAZ)
        * HH Dimensions are:
            * HH By Size - 1, 2, 3 and 4+
            * HH By Workers - 0, 1, 2 and 3+
            * HH By Income Category - 1: [0, 35000); 2: [35000, 75000); 3. [75000, 150000); 4. 150000+
        * For Persons, a match to the total population (HH_POP) by TAZ is attempted via the IPU (Iterational Proportional Update) option using:
            * Age - Three categories. Kids: [0, 17], AdultsUnder65: [18, 64], Seniors: 65+.
*/
Macro "Population Synthesis"(Args)
    on escape, error, notfound do
        ErrorMsg = GetLastError()
        ret_value = 0
        goto quit
    end
    // Set up and run the synthesis
    o = CreateObject("PopulationSynthesis")
    o.RandomSeed = 314159
    
    // Define Seed Data. Specify relationship between HH file and TAZ and between HH and Person file
    o.HouseholdFile({FileName: Args.[PUMS HH Seed], /*Filter: "NP <= 10",*/ ID: "HHID", MatchingID: "PUMA", WeightField: "WGTP"})
    o.PersonFile({FileName: Args.[PUMS Person Seed], ID: "PersonID", HHID: "HHID"})
    
    // Define the marginals data (Disaggregated SED marginals)
    marginalData = {FileName: Args.SEDMarginals, Filter: "HH > 0", ID: "TAZ", MatchingID: "PUMA5"}
    o.MarginalFile(marginalData)     
    o.IPUMarginalFile(marginalData)             

    // ***** HH Dimensions *****
    // HH by Size: Define TAZ marginal fields and corresponding values in the seed data
    // Add Marginal Data Spec
    // 'Field': Field from HH seed file for matching (e.g. NP is the HHSize field in the PUMS HH seed)
    // 'Value': The above array, that specifies the marginal fields and how they are mapped to the seed field
    // 'NewFieldName': The field name in the synthesized outout HH file for this variable
    // Also specify the matching field in the seed data
    HHDimSize = {{Name: "HH_size1", Value: {1, 2}}, 
                 {Name: "HH_size2", Value: {2, 3}}, 
                 {Name: "HH_size3", Value: {3, 4}}, 
                 {Name: "HH_size4", Value: {4, 99}}}
    HHbySizeSpec = {Field: "NP", Value: HHDimSize, NewFieldName: "HHSize"}
    o.AddHHMarginal(HHbySizeSpec)

    // HH by Income (4 categories): Define TAZ marginal fields and corresponding values in the seed data
    HHDimInc = {{Name: "HH_incl" , Value: 1}, 
                {Name: "HH_incml", Value: 2}, 
                {Name: "HH_incmh", Value: 3}, 
                {Name: "HH_inch",  Value: 4}}
    HHbyIncSpec = {Field: "IncomeCategory", Value: HHDimInc, NewFieldName: "IncomeCategory"}
    o.AddHHMarginal(HHbyIncSpec)

    // HH by Number of Workers
    HHDimWrk =   {{Name: "HH_wrk0", Value: {0, 1}}, 
                  {Name: "HH_wrk1", Value: {1, 2}}, 
                  {Name: "HH_wrk2", Value: {2, 3}}, 
                  {Name: "HH_wrk3", Value: {3, 99}}}
    HHbyWrkSpec = {Field: "NumberWorkers", Value: HHDimWrk, NewFieldName: "NumberWorkers"}
    o.AddHHMarginal(HHbyWrkSpec)


    // ***** Add marginals for IPU *****
    // Typically, a good idea to include all of the above HH marginals in the IPU as well
    o.AddIPUHouseholdMarginal(HHbySizeSpec)
    o.AddIPUHouseholdMarginal(HHbyIncSpec)
    o.AddIPUHouseholdMarginal(HHbyWrkSpec)

    // ***** Person Dimensions *****
    // These can only be specified for the IPU procedure. Use three age categories.
    PersonDim =   {{Name: "Kids", Value: {0, 18}}, 
                   {Name: "AdultsUnder65", Value: {18, 65}}, 
                   {Name: "Seniors", Value: {65, 100}}}
    o.AddIPUPersonMarginal({Field: "AgeP", Value: PersonDim, NewFieldName: "Age"})

    // ***** Outputs *****
    // A general note on IPU: 
    // The IPU procedure generally creates a set of weights, one for each TAZ as opposed to a single weight field without IPU
    // These weight fields are used for sampling from the seed
    // Optional outputs include: The IPUIncidenceFile and one weight table for each PUMA
    o.OutputHouseholdsFile = Args.[Synthesized HHs]
    o.ReportExtraHouseholdField("PUMA", "PUMA")
    o.OutputPersonsFile = Args.[Synthesized Persons]
    o.ReportExtraPersonsField("SEX", "Gender") // Add extra field from Person Seed and change the name
    o.ReportExtraPersonsField("ESR", "EmploymentStatus")
    
    // Optional IPU by-products
    outputFolder = Args.[Output Folder] + "\\resident\\population_synthesis\\"
    o.IPUIncidenceOutputFile = outputFolder + "IPUIncidence.bin"
    o.ExportIPUWeights(outputFolder + "IPUWeights")
    o.Tolerance = 0.01
    ret_value = o.Run()

   quit:
    on error, notfound, escape default
    if !ret_value then do
        if ErrorMsg <> null then
            AppendToLogFile(0, ErrorMsg)
    end
    Return(ret_value)
endMacro


/*
    * Macro produces tabulations of marginals at the TAZ level from the population synthesis output
    * Adds HH summary fields to the synhtesied HH file
*/
Macro "PopSynth Post Process"(Args)
    on escape, error, notfound do
        ErrorMsg = GetLastError()
        ret_value = 0
        goto quit
    end

    // Generate tabulations from the synthesis output
    RunMacro("Generate Tabulations", Args)

    objH = CreateObject("AddTables", {TableName: Args.[Synthesized HHs]})
    vw_hh = objH.TableView
    
    objP = CreateObject("AddTables", {TableName: Args.[Synthesized Persons]})
    vw_per = objP.TableView
    
    // Create Balloon Help on synthesized tables
    RunMacro("Set Balloon Help", vw_hh, vw_per)
    BuildInternalIndex(GetFieldFullSpec(vw_hh, "HouseholdID"))
    BuildInternalIndex(GetFieldFullSpec(vw_hh, "ZoneID"))
    BuildInternalIndex(GetFieldFullSpec(vw_per, "PersonID"))
    BuildInternalIndex(GetFieldFullSpec(vw_per, "HouseholdID"))

    ret_value = 1
 quit:
    on escape, error, notfound default
    if !ret_value then do
        if ErrorMsg <> null then
            AppendToLogFile(0, ErrorMsg)
    end
    Return(ret_value)
endMacro


Macro "Set Balloon Help"(vw_hh, vw_per)
    // HH Field Descriptions
    desc = null
    desc.ZoneID = "TRM TAZ ID"
    desc.IncomeCategory = "Household Income Category:|1. Income [0, 35K)|2. Income [35K, 70K)|3. Income [70K, 150K)| 4. Income 150K+"
    strct = GetTableStructure(vw_hh, {"Include Original" : "True"})
    for i = 1 to strct.length do
        fld_name = strct[i][1]
        strct[i][8] = desc.(fld_name)
    end
    ModifyTable(vw_hh, strct)
    
    // Person Field descriptions
    desc = null
    desc.Gender = "Gender:|1. Male|2. Female"
    desc.EmploymentStatus = "Employment status recode|1. Civilian employed, at work|2. Civilian employed, with a job but not at work|3. Unemployed|"
    desc.EmploymentStatus = desc.EmploymentStatus + "4. Armed forces, at work|5. Armed forces, with a job but not at work|6. Not in labor force|Missing. N/A (less than 16 years old)"	
    strct = GetTableStructure(vw_per, {"Include Original" : "True"})
    for i = 1 to strct.length do
        fld_name = strct[i][1]
        strct[i][8] = desc.(fld_name)
    end
    ModifyTable(vw_per, strct)
endMacro


Macro "Generate Tabulations"(Args)
    
    outFile = Args.[Synthesized Tabulations]

    // Open HH File and create empty output fields for number of kids, seniors, adults and workers in the HH
    objH = CreateObject("AddTables", {TableName: Args.[Synthesized HHs]})
    vw_hh = objH.TableView
    modify = CreateObject("CC.ModifyTableOperation", vw_hh)
    modify.FindOrAddField("HHAdultsUnder65", "Long", 12,,)
    modify.FindOrAddField("HHKids", "Long", 12,,)
    modify.FindOrAddField("HHSeniors", "Long", 12,,)
    modify.FindOrAddField("HHWorkers", "Long", 12,,)
    modify.Apply()
    {hhFlds, hhSpecs} = GetFields(vw_hh,)

    objP = CreateObject("AddTables", {TableName: Args.[Synthesized Persons]})
    vw_per = objP.TableView

    // Export to In-memory View for faster processing
    vw_hhM = ExportView(vw_hh + "|", "MEM", "HHMem",,{"Indexed Fields": {"HouseholdID"}})
    vw_perM = ExportView(vw_per + "|", "MEM", "PersonMem",,{"Indexed Fields": {"HouseholdID"}})
    objH = null
    objP = null
    
    // Write number of adults, kids, seniors and workers in the synthesized HH table (by aggregation on the synthesized persons)
    expr1 = CreateExpression(vw_perM, "Kid", "if Age < 18 then 1 else 0",)
    expr2 = CreateExpression(vw_perM, "AdultUnder65", "if Age >= 18 and Age < 65 then 1 else 0",)
    expr3 = CreateExpression(vw_perM, "Senior", "if Age >= 65 then 1 else 0",)
    expr4 = CreateExpression(vw_perM, "Worker", "if EmploymentStatus = 1 or EmploymentStatus = 2 or EmploymentStatus = 4 or EmploymentStatus = 5 then 1 else 0",)
    
    // Aggregate person table by 'HouseholdID' and sum the above expression fields
    aggrSpec = {{"Kid", "sum",}, {"AdultUnder65", "sum",}, {"Senior", "sum",}, {"Worker", "sum",}}
    vwA =  AggregateTable("MemAggr", vw_perM + "|", "MEM",, "HouseholdID", aggrSpec,)
    {flds, specs} = GetFields(vwA,)
    
    // Join aggregation file to HH table and copy over values
    vwJ = JoinViews("Aggr_HH", specs[1], GetFieldFullSpec(vw_hhM, "HouseholdID"),)
    vecs = GetDataVectors(vwJ + "|", {"Kid", "AdultUnder65", "Senior", "Worker"}, {OptArray: 1})
    vecsSet.HHKids = vecs.Kid
    vecsSet.HHAdultsUnder65 = vecs.AdultUnder65
    vecsSet.HHSeniors = vecs.Senior
    vecsSet.HHWorkers = vecs.Worker
    SetDataVectors(vwJ +"|", vecsSet,)
    CloseView(vwJ)
    CloseView(vwA)

    /* Preferred code to replace Lines 190-210, but is much slower. Takes 90 seconds as opposed to 14 seconds for the above snippet
    o = CreateObject("TransCAD.ABM")
    o.TargetFile({ViewName: vw_hhM, ID: "HouseholdID"})
    o.SourceFile({ViewName: vw_perM, ID: "HouseholdID"})
    o.FillTargetField({Filter: "Age < 18", FillField: "HHKids",    DefaultValue: 0})
    o.FillTargetField({Filter: "Age >= 65", FillField: "HHSeniors", DefaultValue: 0})
    o.FillTargetField({Filter: "Age >= 18 and Age < 65", FillField: "HHAdultsUnder65",  DefaultValue: 0})
    o.FillTargetField({Filter: "EmploymentStatus = 1 or EmploymentStatus = 2 or EmploymentStatus = 4 or EmploymentStatus = 5", FillField: "HHWorkers",  DefaultValue: 0})
    o = null*/
    
    // Create Expressions on output HH for tabulations
    specs = null
    specs = {{Fields: {"HH_size1", "HH_size2", "HH_size3", "HH_size4"}, MatchingField: "HHSize", Levels: {1,2,3,4}},
             {Fields: {"HH_wrk0", "HH_wrk1", "HH_wrk2", "HH_wrk3"},     MatchingField: "NumberWorkers", Levels: {0,1,2,3}},
             {Fields: {"HH_incl", "HH_incml", "HH_incmh", "HH_inch"},   MatchingField: "IncomeCategory", Levels: {1,2,3,4}}
             }
    aggflds = RunMacro("Create Output HH Expressions", vw_hhM, specs)
    aggflds = aggflds + {{"HHSize", "sum",},
                         {"HHAdultsUnder65", "sum",},
                         {"HHKids", "sum",},
                         {"HHSeniors", "sum",},
                         {"HHWorkers", "sum",}} // For HH_Pop and number of adults, kids, seniors and workers

    // Aggregate HH Data
    vw_agg1 = AggregateTable("HHTotals", vw_hhM + "|", "MEM", "Agg1", "ZoneID", aggflds, null)
    ExportView(vw_agg1 + "|", "FFB", outFile,,)
    CloseView(vw_agg1)

    // Change field name in final tabulation file
    obj = CreateObject("AddTables", {TableName: outFile})
    vw = obj.TableView
    modify = CreateObject("CC.ModifyTableOperation", vw)
    modify.ChangeField("HHSize", {Name: "HH_Pop"})
    modify.ChangeField("HHAdultsUnder65", {Name: "AdultsUnder65"})
    modify.ChangeField("HHKids", {Name: "Kids"})
    modify.ChangeField("HHSeniors", {Name: "Seniors"})
    modify.ChangeField("HHWorkers", {Name: "Workers"})
    modify.Apply()
    obj = null

    // Export the HH In-Memory table back
    ExportView(vw_hhM + "|", "FFB", Args.[Synthesized HHs], hhFlds,)
    CloseView(vw_hhM)
    CloseView(vw_perM)
endMacro


// Generates formula fields for tabulations
Macro "Create Output HH Expressions"(vw_hhM, specs)
    aggflds = null
    for spec in specs do
        flds = spec.Fields
        keyFld = spec.MatchingField
        bounds = spec.Levels
        nClasses = flds.length
        for i = 1 to nClasses - 1 do
            CreateExpression(vw_hhM, flds[i], "if " + keyFld + " = " + String(bounds[i]) + " then 1 else 0",)
            aggflds = aggflds + {{flds[i], "sum",}}
        end
        CreateExpression(vw_hhM, flds[nClasses], "if " + keyFld + " >= " + String(bounds[nClasses]) + " then 1 else 0",)
        aggflds = aggflds + {{flds[nClasses], "sum",}}
    end
    Return(aggflds)
endMacro
