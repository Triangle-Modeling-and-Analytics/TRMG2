Macro "Model.Attributes"

Attributes = {{"BannerHeight",80},
                  {"BannerWidth",2000},
                  {"BannerPicture","src\\flow_chart\\bmp\\banner.bmp"},
                  {"HideBanner",0},
                  {"Base Scenario Name","Model"},
                  {"ClearLogFiles",1},
                  {"CodeUI","src\\trmg2.dbd"},
                  {"ExpandStages","Side by Side"},
                  {"MaxProgressBars",2},
                  {"MinItemSpacing",20},
                  {"Output Folder Format","Output Folder\\Scenario Name"},
                  {"Output Folder Parameter","Output Folder"},
                  {"Output Folder Per Run","No"},
                  {"Picture","bmp\\TransCAD_Model.bmp"},
                  {"ReportAfterStep",0},
                  {"Requires",{{"Program","TransCAD"},
                  {"Version",9},
                  {"Build",32650}}},
                  {"Shape","Rectangle"},
                  {"Time Stamp Format","yyyyMMdd_HHmm"}}


endMacro 

Macro "Model.Step" (Args,Result)
    Attributes = {{"FrameColor",{255,255,255}},
                  {"Height",45},
                  {"PicturePosition","CenterRight"},
                  {"TextFont","Calibri|12|400|000000|0"},
                  {"Width",225}}
EndMacro


Macro "Model.Arrow" (Args,Result)
    Attributes = {{"ArrowHead","Triangle"},
                  {"ArrowHeadSize",8}}
EndMacro

Macro "Model.OnStepStart" (Args,Result)
Body:
    // Initialize choice model sources object
    flowchart = RunMacro("GetFlowChart")
    {drive, path, name, ext} = SplitPath(flowchart.UI)

    // Execute this macro just before running each step. Have to do it here because the parameters (file names/locations) could have changed.
    Opts = null
    Opts.MatrixSources = Args.MatrixSources
    Opts.TableSources = Args.TableSources
    Opts.Joins = Args.Joins
    Opts.SourceKeys = Args.SourceKeys 
        
    SetLibrary(drive + path + "src/trmg2.dbd")
    srcObj = CreateObject("Choice Model Sources", Args, Opts)
    SetLibrary()

    Args.SourcesObject = srcObj
EndMacro


/**
    Return an option array of parameters that will be stored in the Args array at runtime
**/
// if needed, can email status at every step
Macro "Model.OnStepDone" (Args,Result,StepName)
Body:
    // RunMacro("SendMail", Args, "MSA Model Checkpoint", StepName)
    Args.SourcesObject = null
    return(1)
EndMacro


// when the model is done, email the summary report
Macro "Model.OnModelDone" (Args,Result,CompletedSteps)
Body:

    rep = Args.[Report File]
    xsl = "report.xsl"
    // convert the XML report to a HTML file
    BodyFile = RunMacro("XML2HTML", rep, xsl, )
    // RunMacro("SendMail", Args, "MSA Model Report", , BodyFile)
    return(1)
EndMacro


Macro "Model.OnModelStart" (Args,Result)
Body:
    on error do
        Args.SendEmails = 0
        goto skipemails
    end

    // check if user wants to send emails at checkpoints.
    if Args.SendEmails <> 0 then do 
        ServerName = Args.[SMTPServer]
        PortNumber = Args.PortNumber

        // configure mail client
        if Args.mailObj = null then do
            mail = CreateObject("Utilities.Mail", {Server: ServerName, Port: PortNumber})
            mail.UseDefaultCredentials = false
            mail.ResetCredentials() // every time the model is launched, reset the credentials. If credentials are needed a dbox will popup
            end
        end
    skipemails:
    on error default

    Return(Runtime_Args)
EndMacro

macro "Model.OnModelLoad" (Args, Results)
Body:
    flowchart = RunMacro("GetFlowChart")
    { drive , path , name , ext } = SplitPath(flowchart.UI)
    rootFolder = drive + path

    ui_DB = rootFolder + "src\\trmg2.dbd"
    srcFile = rootFolder + "src\\_TRMCompile.lst"
    RunMacro("CompileGISDKCode", {Source: srcFile, UIDB: ui_DB, Silent: 0, ErrorMessage: "Error compiling code"})
endmacro 

Macro "Model.OnModelReady" (Args,Result)
Body:

    // on error do
    //     on error default
    // end

    // mail = CreateObject("Utilities.Mail", {Server: ServerName, Port: PortNumber})
    // mail.UseDefaultCredentials = false
    // mail.ResetCredentials() // every time the model is launched, reset the credentials. If credentials are needed a dbox will popup

    Return()
EndMacro