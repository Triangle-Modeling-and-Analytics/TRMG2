/*
University Model
*/

Macro "University" (Args)
    // RunMacro("University Productions", Args)
    // RunMacro("University Attractions", Args)
    // RunMacro("University Balance Ps and As", Args)
    // RunMacro("University TOD", Args)
    // RunMacro("University Gravity", Args)
    // RunMacro("University Combine Matrix", Args)
    // RunMacro("University Directionality", Args)
    // RunMacro("University MC Probabilities", Args)
    // RunMacro("University Mode Choice", Args)
    // ShowMessage("done")
    return(1)
endmacro

/*
Calculate university productions
*/

Macro "University Productions" (Args)
    se_file = Args.SE
    production_rate_file = Args.[Input Folder] + "\\university\\university_production_rates.csv"

    campus_list = {"NCSU", "UNC", "DUKE", "NCCU"}

    se_vw = OpenTable("se", "FFB", {se_file})

    data = GetDataVectors(
        se_vw + "|",
        {
            "StudGQ_NCSU",
            "StudGQ_UNC",
            "StudGQ_DUKE",
            "StudGQ_NCCU",
            "StudOff_NCSU",
            "StudOff_UNC",
            "StudOff_DUKE",
            "StudOff_NCCU",
            "BuildingS_NCSU",
            "BuildingS_UNC",
            "BuildingS_DUKE",
            "BuildingS_NCCU"
        },
        {OptArray: TRUE}
    )

    // read university production rate file
    rate = RunMacro("Read Parameter File", {
        file: production_rate_file,
        names: "variable",
        values: "rate"
    })

    SetView(se_vw)

    for c = 1 to campus_list.length do
        campus = campus_list[c]

        //UHC: Home-Based-Campus
        //UHO: Home-Based-Other
        //UCO: Campus-Based-Other
        //UC1: On-Campus
        //UCC: Inter-Campus
        //UOO: University student Other-Other

        production_uhc_on = data.("StudGQ_" + campus) * rate.Prod_Rate_UHC_On
        production_uhc_off = data.("StudOff_" + campus) * rate.Prod_Rate_UHC_Off

        production_uho_on = data.("StudGQ_" + campus) * rate.Prod_Rate_UHO_On
        production_uho_off = data.("StudOff_" + campus) * rate.Prod_Rate_UHO_Off

        production_uco = data.("BuildingS_" + campus) * rate.Prod_Rate_UCO
        production_ucc = data.("BuildingS_" + campus) * rate.Prod_Rate_UCC
        production_uc1 = data.("BuildingS_" + campus) * rate.Prod_Rate_UC1

        a_fields = {
            {"ProdOn_UHC_" + campus, "Real", 10, 2, , , , campus + " UHC OnCampus Students Production"},
            {"ProdOff_UHC_" + campus, "Real", 10, 2, , , , campus + " UHC OffCampus Students Production"},
            {"ProdOn_UHO_" + campus, "Real", 10, 2, , , , campus + " UHO OnCampus Students Production"},
            {"ProdOff_UHO_" + campus, "Real", 10, 2, , , , campus + " UHO OffCampus Students Production"},

            {"Prod_UCO_" + campus, "Real", 10, 2, , , , campus + " UCO Production"},
            {"Prod_UC1_" + campus, "Real", 10, 2, , , , campus + " UC1 Production"},
            {"Prod_UCC_" + campus, "Real", 10, 2, , , , campus + " UCC Production"}
        }
        RunMacro("Add Fields", {view: se_vw, a_fields: a_fields})

        SetDataVector(se_vw + "|", "ProdOn_UHC_" + campus, production_uhc_on, )
        SetDataVector(se_vw + "|", "ProdOff_UHC_" + campus, production_uhc_off, )
        SetDataVector(se_vw + "|", "ProdOn_UHO_" + campus, production_uho_on, )
        SetDataVector(se_vw + "|", "ProdOff_UHO_" + campus, production_uho_off, )
        SetDataVector(se_vw + "|", "Prod_UCO_" + campus, production_uco, )
        SetDataVector(se_vw + "|", "Prod_UC1_" + campus, production_uc1, )
        SetDataVector(se_vw + "|", "Prod_UCC_" + campus, production_ucc, )
    end

    CloseView(se_vw)

endmacro

/*
Calculate university attractions
*/

Macro "University Attractions" (Args)
    se_file = Args.SE
    rate_file = Args.[Input Folder] + "\\university\\university_attraction_rates.csv"

    campus_list = {"NCSU", "UNC", "DUKE", "NCCU"}

    se_vw = OpenTable("se", "FFB", {se_file})

    data = GetDataVectors(
        se_vw + "|",
        {
            "StudOff_NCSU",
            "StudOff_UNC",
            "StudOff_DUKE",
            "StudOff_NCCU",
            "BuildingS_NCSU",
            "BuildingS_UNC",
            "BuildingS_DUKE",
            "BuildingS_NCCU",
            "Retail"
        },
        {OptArray: TRUE}
    )

    // read university attraction model file for coefficients
    uho_on_coeff = RunMacro("Read Parameter File", {file: rate_file, names: "variable", values: "uho_on"})
    uho_off_coeff = RunMacro("Read Parameter File", {file: rate_file, names: "variable", values: "uho_off"})
    uco_coeff = RunMacro("Read Parameter File", {file: rate_file, names: "variable", values: "uco"})

    SetView(se_vw)

    for c = 1 to campus_list.length do
        campus = campus_list[c]

        //share of campus bldg sqft among zones
        proportion_bldg_sqft_campus = data.("BuildingS_" + campus) / data.("BuildingS_" + campus).sum()

        // UHC on-campus students attractions
        attraction_uhc_on = proportion_bldg_sqft_campus

        // UHC off-campus students attractions
        attraction_uhc_off = proportion_bldg_sqft_campus

        // UHO on-campus students attractions
        attraction_uho_on = uho_on_coeff.intercept +
            uho_on_coeff.retail_employment * data.Retail +
            uho_on_coeff.student_off_campus * data.("StudOff_" + campus)

        // UHO off-campus students attractions
        attraction_uho_off = uho_off_coeff.intercept +
            uho_off_coeff.retail_employment * data.Retail +
            uho_off_coeff.student_off_campus * data.("StudOff_" + campus)

        // UCO attractions
        attraction_uco = uco_coeff.intercept +
            uco_coeff.retail_employment * data.Retail +
            uco_coeff.student_off_campus * data.("StudOff_" + campus)

        // UCC attractions
        attraction_ucc = proportion_bldg_sqft_campus

        // UC1 attractions
        attraction_uc1 = proportion_bldg_sqft_campus

        a_fields = {
            {"AttrOn_UHC_" + campus, "Real", 10, 2, , , , campus + " UHC OnCampus Students Attraction"},
            {"AttrOff_UHC_" + campus, "Real", 10, 2, , , , campus + " UHC OffCampus Students Attraction"},
            {"AttrOn_UHO_" + campus, "Real", 10, 2, , , , campus + " UHO OnCampus Students Attraction"},
            {"AttrOff_UHO_" + campus, "Real", 10, 2, , , , campus + " UHO OffCampus Students Attraction"},
            {"Attr_UCO_" + campus, "Real", 10, 2, , , , campus + " UCO Attraction"},
            {"Attr_UCC_" + campus, "Real", 10, 2, , , , campus + " UCC Attraction"},
            {"Attr_UC1_" + campus, "Real", 10, 2, , , , campus + " UC1 Attraction"}
        }
        RunMacro("Add Fields", {view: se_vw, a_fields: a_fields})

        SetDataVector(se_vw + "|", "AttrOn_UHC_" + campus, attraction_uhc_on, )
        SetDataVector(se_vw + "|", "AttrOff_UHC_" + campus, attraction_uhc_off, )
        SetDataVector(se_vw + "|", "AttrOn_UHO_" + campus, attraction_uho_on, )
        SetDataVector(se_vw + "|", "AttrOff_UHO_" + campus, attraction_uho_off, )
        SetDataVector(se_vw + "|", "Attr_UCO_" + campus, attraction_uco, )
        SetDataVector(se_vw + "|", "Attr_UCC_" + campus, attraction_ucc, )
        SetDataVector(se_vw + "|", "Attr_UC1_" + campus, attraction_uc1, )
    end

endmacro

/*
Balance university production and attraction
*/

Macro "University Balance Ps and As" (Args)
    se_file = Args.SE

    se_vw = OpenTable("se", "FFB", {se_file})
    SetView(se_vw)

    campus_list = {"NCSU", "UNC", "DUKE", "NCCU"}

    for c = 1 to campus_list.length do
        campus = campus_list[c]

        production_uhc_on = GetDataVector(se_vw + "|", "ProdOn_UHC_" + campus, )
        production_uhc_off = GetDataVector(se_vw + "|", "ProdOff_UHC_" + campus, )
        production_uho_on = GetDataVector(se_vw + "|", "ProdOn_UHO_" + campus, )
        production_uho_off = GetDataVector(se_vw + "|", "ProdOff_UHO_" + campus, )
        production_uco = GetDataVector(se_vw + "|", "Prod_UCO_" + campus, )
        production_ucc = GetDataVector(se_vw + "|", "Prod_UCC_" + campus, )
        production_uc1 = GetDataVector(se_vw + "|", "Prod_UC1_" + campus, )

        attraction_uhc_on = GetDataVector(se_vw + "|", "AttrOn_UHC_" + campus, )
        attraction_uhc_off = GetDataVector(se_vw + "|", "AttrOff_UHC_" + campus, )
        attraction_uho_on = GetDataVector(se_vw + "|", "AttrOn_UHO_" + campus, )
        attraction_uho_off = GetDataVector(se_vw + "|", "AttrOff_UHO_" + campus, )
        attraction_uco = GetDataVector(se_vw + "|", "Attr_UCO_" + campus, )
        attraction_ucc = GetDataVector(se_vw + "|", "Attr_UCC_" + campus, )
        attraction_uc1 = GetDataVector(se_vw + "|", "Attr_UC1_" + campus, )

        production_uhc_on_total = VectorStatistic(production_uhc_on, "sum", )
        production_uhc_off_total = VectorStatistic(production_uhc_off, "sum", )
        production_uho_on_total = VectorStatistic(production_uho_on, "sum", )
        production_uho_off_total = VectorStatistic(production_uho_off, "sum", )
        production_uco_total = VectorStatistic(production_uco, "sum", )
        production_ucc_total = VectorStatistic(production_ucc, "sum", )
        production_uc1_total = VectorStatistic(production_uc1, "sum", )

        attraction_uhc_on_total = VectorStatistic(attraction_uhc_on, "sum", )
        attraction_uhc_off_total = VectorStatistic(attraction_uhc_off, "sum", )
        attraction_uho_on_total = VectorStatistic(attraction_uho_on, "sum", )
        attraction_uho_off_total = VectorStatistic(attraction_uho_off, "sum", )
        attraction_uco_total = VectorStatistic(attraction_uco, "sum", )
        attraction_ucc_total = VectorStatistic(attraction_ucc, "sum", )
        attraction_uc1_total = VectorStatistic(attraction_uc1, "sum", )

        // balancing to productions
        attraction_uhc_on = attraction_uhc_on * production_uhc_on_total/attraction_uhc_on_total
        attraction_uhc_off = attraction_uhc_off * production_uhc_off_total/attraction_uhc_off_total
        attraction_uho_on = attraction_uho_on * production_uho_on_total/attraction_uho_on_total
        attraction_uho_off = attraction_uho_off * production_uho_off_total/attraction_uho_off_total
        attraction_uco = attraction_uco * production_uco_total/attraction_uco_total
        attraction_ucc = attraction_ucc * production_ucc_total/attraction_ucc_total
        attraction_uc1 = attraction_uc1 * production_uc1_total/attraction_uc1_total

        SetDataVector(se_vw + "|", "AttrOn_UHC_" + campus, attraction_uhc_on, )
        SetDataVector(se_vw + "|", "AttrOff_UHC_" + campus, attraction_uhc_off, )
        SetDataVector(se_vw + "|", "AttrOn_UHO_" + campus, attraction_uho_on, )
        SetDataVector(se_vw + "|", "AttrOff_UHO_" + campus, attraction_uho_off, )
        SetDataVector(se_vw + "|", "Attr_UCO_" + campus, attraction_uco, )
        SetDataVector(se_vw + "|", "Attr_UCC_" + campus, attraction_ucc, )
        SetDataVector(se_vw + "|", "Attr_UC1_" + campus, attraction_uc1, )

    end

    CloseView(se_vw)

endmacro

/*
Split university balanced productions and attractions by time periods
*/

Macro "University TOD" (Args)
    se_file = Args.SE
    tod_file = Args.[Input Folder] + "\\university\\university_tod.csv"

    se_vw = OpenTable("se", "FFB", {se_file})

    {drive, folder, name, ext} = SplitPath(tod_file)

    RunMacro("Create Sum Product Fields", {
        view: se_vw, factor_file: tod_file,
        field_desc: "University Productions and Attractions by Time of Day|See " + name + ext + " for details."
    })

    CloseView(se_vw)
endmacro

/*
University Gravity Distribution
*/

Macro "University Gravity" (Args)
    se_file = Args.SE
    param_file = Args.[Input Folder] + "\\university\\university_gravity.csv"
    skim_file =  Args.[Output Folder] + "\\skims\\roadway\\skim_sov_AM.mtx"
    university_matrix_file = Args.[Output Folder] + "\\university\\university_pa_trips.mtx"

    opts = null
    opts.se_file = se_file
    opts.param_file = param_file
    opts.skim_file = skim_file
    opts.output_matrix = university_matrix_file
    RunMacro("Gravity", opts)
endmacro

/*
Combine university trips for all campus and create period specific matrices
*/

Macro "University Combine Matrix" (Args)
    trips_dir = Args.[Output Folder] + "\\university\\"
    periods = Args.periods

    campus_list = {"NCSU", "UNC", "DUKE", "NCCU"}

    university_mtx_file = trips_dir + "university_pa_trips.mtx"

    out_core_names = {"UHC_ON", "UHC_OFF", "UHO_ON", "UHO_OFF", "UCO", "UCC", "UC1"}

    for period in periods do
        out_mtx_file = trips_dir + "university_pa_trips_" + period + ".mtx"
        if GetFileInfo(out_mtx_file) <> null then DeleteFile(out_mtx_file)

        univ_mtx = OpenMatrix(university_mtx_file, )
        mc = CreateMatrixCurrency(univ_mtx,,,,)

        matOpts = {{"File Name", out_mtx_file}, {"Label", "University " + period + " Trips Matrix"}, {"File Based", "Yes"}, {"Tables", out_core_names}}

        out_mtx = CopyMatrixStructure({mc}, matOpts)

        mc = null
        univ_mtx = null
        out_mtx = null

        univ_mtx = CreateObject("Matrix")
        univ_mtx.LoadMatrix(university_mtx_file)

        out_mtx = CreateObject("Matrix")
        out_mtx.LoadMatrix(out_mtx_file)

        cores = univ_mtx.data.cores
        out_cores = out_mtx.data.cores

        // initilize with zero
        for core in out_core_names do
            out_cores.(core) := 0
        end

        // add purpose trips by campus
        for campus in campus_list do
            for core in out_core_names do
                out_cores.(core) := out_cores.(core) + Nz(cores.(core + "_" + campus + "_" + period))
            end
        end

    end

    cores = null
    out_cores = null
    univ_mtx = null
    out_mtx = null

    DeleteFile(university_mtx_file)
endmacro

/*
Convert from PA to OD format
*/

Macro "University Directionality" (Args)
    trips_dir = Args.[Output Folder] + "\\university\\"
    dir_factor_file = Args.[Input Folder] + "\\university\\university_directionality.csv"
    periods = Args.periods

    fac_vw = OpenTable("dir", "CSV", {dir_factor_file})

    dir_factors = RunMacro("Read Parameter File", {
        file: dir_factor_file,
        names: "period",
        values: "pa_factor"
    })

    for period in periods do
        pa_matrix_file = trips_dir + "university_pa_trips_" + period + ".mtx"
        od_matrix_file = trips_dir + "university_trips_" + period + ".mtx"
        od_transpose_matrix_file = trips_dir + "university_transpose_trips_" + period + ".mtx"

        CopyFile(pa_matrix_file, od_matrix_file)

        mat = OpenMatrix(od_matrix_file, )
        tmat = TransposeMatrix(mat, {
            {"File Name", od_transpose_matrix_file},
            {"Label", "Transposed Trips"},
            {"Type", "Double"}}
        )

        mat = null
        tmat = null

        mtx = CreateObject("Matrix")
        mtx.LoadMatrix(od_matrix_file)
        mtx_core_names = mtx.data.CoreNames
        cores = mtx.data.cores

        t_mtx = CreateObject("Matrix")
        t_mtx.LoadMatrix(od_transpose_matrix_file)
        t_cores = t_mtx.data.cores

        pa_factor = dir_factors.(period)

        for core_name in mtx_core_names do
            cores.(core_name) := Nz(cores.(core_name)) * pa_factor + Nz(t_cores.(core_name)) * (1 - pa_factor)
        end

        cores = null
        t_cores = null
        mtx = null
        t_mtx = null

        DeleteFile(pa_matrix_file)
        DeleteFile(od_transpose_matrix_file)

    end

endmacro

/*
Calculates mode choice probabilities for university trips
*/

Macro "University MC Probabilities" (Args)
    input_dir = Args.[Input Folder] + "\\university\\mode"
    skims_dir = Args.[Output Folder] + "\\skims"
    output_dir = Args.[Output Folder] + "\\university\\mode"
    periods = Args.periods
    parking_logsum_table = Args.[Parking Logsums Table]

    RunMacro("Create Directory", output_dir)

    trip_types = {"UHC", "UHO", "UCO", "UCC", "UC1"}

    for trip_type in trip_types do
        trip_type = Lower(trip_type)
        opts = null
        opts.primary_spec = {Name: "transit_skim"}
        opts.trip_type = trip_type
        opts.util_file = input_dir + "\\" + "univ_mc_" + trip_type + ".csv"

        if trip_type = "uhc" or trip_type = "uho" then opts.segments = {"on", "off"}

        for period in periods do
            opts.period = Lower(period)
            sov_skim = skims_dir + "\\roadway\\skim_sov_" + period + ".mtx"
            transit_skim = skims_dir + "\\transit\\skim_" + period + "_w_lb.mtx"
            walk_skim = skims_dir + "\\nonmotorized\\walk_skim.mtx"
            /*
            opts.tables = {
                parking: {File: parking_logsum_table, IDField: "TAZ"}
            }
            */
            opts.matrices = {
                sov_skim: {File: sov_skim},
                transit_skim: {File: transit_skim},
                walk_skim: {File: walk_skim}
            }

            opts.output_dir = output_dir

            RunMacro("MC", opts)
        end
    end
endmacro

/*
Apply mode choice probabilities to split university trips by mode
*/

Macro "University Mode Choice" (Args)
    trips_dir = Args.[Output Folder] + "\\university\\"
    periods = Args.periods

    mode_names = {"auto", "transit", "walk", "bike"}

    for period in periods do
        univ_mtx_file = trips_dir + "university_trips_" + period + ".mtx"

        univ_mtx = OpenMatrix(univ_mtx_file, )
        mc = CreateMatrixCurrency(univ_mtx,,,,)
        trip_types = GetMatrixCoreNames(univ_mtx)

        out_mtx_file = trips_dir + "university_mode_trips_" + period + ".mtx"
        if GetFileInfo(out_mtx_file) <> null then DeleteFile(out_mtx_file)

        matOpts = {{"File Name", out_mtx_file}, {"Label", "University " + period + " Trips By Mode"}, {"File Based", "Yes"}, {"Tables", mode_names}}

        out_mtx = CopyMatrixStructure({mc}, matOpts)
        out_mcs = CreateMatrixCurrencies(out_mtx,,,)

        for mode in mode_names do
            out_mcs.(mode) := 0
        end

        mc = null
        univ_mtx = null
        out_mcs = null
        out_mtx = null

        for trip_type in trip_types do
            mc_mtx_file = trips_dir + "\\mode\\probabilities\\probability_" + Lower(trip_type) + "_" + Lower(period) + ".mtx"

            mc_mtx = CreateObject("Matrix")
            mc_mtx.LoadMatrix(mc_mtx_file)
            mc_cores = mc_mtx.data.cores

            out_mtx = CreateObject("Matrix")
            out_mtx.LoadMatrix(out_mtx_file)
            out_cores = out_mtx.data.cores

            univ_mtx = CreateObject("Matrix")
            univ_mtx.LoadMatrix(univ_mtx_file)
            univ_cores = univ_mtx.data.cores

            for mode in mode_names do
                out_cores.(mode) := Nz(out_cores.(mode)) + Nz(univ_cores.(trip_type)) * Nz(mc_cores.(mode))
            end

            mc_cores = null
            mc_mtx = null
            out_cores = null
            out_mtx = null
            univ_cores = null
            univ_mtx = null

        end
    end
endmacro
