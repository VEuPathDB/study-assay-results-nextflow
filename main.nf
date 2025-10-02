#!/usr/bin/env nextflow

nextflow.preview.recursion = true

nextflow.enable.dsl = 2

import groovy.json.JsonSlurper;

params.tpmDir = params.tpmDir ? params.tpmDir : "$projectDir/NO_FILE";

//def containerMap = [:]
def containerMap = [
       1: 'veupathdb/gusenv:latest',
       2: 'veupathdb/iterativewgcna:latest',
   ]




process PARSE_XML_CONFIG {
    container 'veupathdb/bioperl:latest'

    input:
    path xml_file

    output:
    path "steps.json", emit: step_queue

    script:
    """
    #!/usr/bin/perl
    use CBIL::StudyAssayResults::XmlParser;
    my \$xmlParser = CBIL::StudyAssayResults::XmlParser->new("$xml_file");
    \$xmlParser->printToJsonFile();
    """
}


process MAIN_WORKING_DIRECTORY {
    container 'veupathdb/alpine_bash:latest'

    input:
    path finalDir
    path tpmDir

    output:
    path "main_working_directory"
    
    script:
    if(tpmDir.name != "NO_FILE") {
        """
        mkdir -p main_working_directory/analysis_output
        original_final=\$(readlink -f $finalDir)
        original_tpm=\$(readlink -f $tpmDir)        
        ln -s \$original_final main_working_directory/
        ln -s \$original_tpm main_working_directory/
        """
    }
    else {
        """
        mkdir -p main_working_directory/analysis_output
        original_final=\$(readlink -f $finalDir)
        ln -s \$original_final main_working_directory/
        """
    }

}




process DO_STEP {

    container { containerMap.get(stepNumber++) }

    maxForks 1

    input:
    path(jsonFile, stageAs: "step_json_file.json")
    path(remainingStepsFile, stageAs: "input_remaining_steps.json")
    path mainWorkingDirectory
    val stepNumber

    output:
    path "outputRemainingStepsFile.json", emit: remainingSteps
    path mainWorkingDirectory, emit: mainWorkingDirectory
    val stepNumber, emit: stepNumber

    script:
    """
    cp $remainingStepsFile outputRemainingStepsFile.json
    touch outputRemainingStepsFile.json
    """
}

process NEXT_STEP {
    container 'veupathdb/bioperl:latest'

    input:
    path(jsonFile, stageAs: "input_json_file.json")

    output:
    path('nextStep.json')
    path('remainingSteps.json')

    script:
    """
    nextStepFromJsonFile.pl $jsonFile nextStep.json remainingSteps.json
    """
    
}


workflow {
    
    analysisConfigXml = Channel.fromPath(params.analysisConfigFile, checkIfExists: true)

    def stepNumber = 1;

    MAIN_WORKING_DIRECTORY(params.finalDir, params.tpmDir)

    PARSE_XML_CONFIG(
        analysisConfigXml
    )

    ANALYZE_STEPS
        .recurse(PARSE_XML_CONFIG.out.collect(), MAIN_WORKING_DIRECTORY.out, stepNumber)
        .times (2)

}


workflow ANALYZE_STEPS {
    take:
    stepsJson
    mainWorkingDirectory
    stepNumber

    main:
    stepConfig = NEXT_STEP(stepsJson)

    // withContainer = stepConfig.map { it ->
    //     containerName = containerNameFromStep(it[0])
    //     return [it[0], it[1], containerName]
    // }

//    containerName = stepConfig.nextStep.map { stepFile ->
//        return containerNameFromStep(stepFile)
//    }

    DO_STEP(stepConfig, mainWorkingDirectory, stepNumber)


    emit:
    DO_STEP.out.remainingSteps
    DO_STEP.out.mainWorkingDirectory
    DO_STEP.out.stepNumber
}


// def containerNameFromStep(stepJson) {
//     def jsonSlurper = new JsonSlurper()
//     def jsonData = jsonSlurper.parse(stepJson)
//     def dynamicContainer = 'veupathdb/gusenv:latest';
//     if(jsonData.class == "ApiCommonData::Load::IterativeWGCNAResults") {
//         dynamicContainer = 'veupathdb/iterativewgcna:latest'
//     }
//     return dynamicContainer
// }


// def countSteps(stepJson) {
//     def jsonSlurper = new JsonSlurper()
//     def jsonData = jsonSlurper.parse(stepJson)
//     if (jsonData instanceof List) {
//         return jsonData.size()
//     } else {
//         // Handle case where jsonData is not an array, if necessary
//         return 0
//     }

// }
