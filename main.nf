#!/usr/bin/env nextflow

nextflow.preview.recursion = true

nextflow.enable.dsl = 2

import groovy.json.JsonSlurper;
import groovy.xml.XmlSlurper;

params.tpmDir = params.tpmDir ? params.tpmDir : "$projectDir/NO_FILE";

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

    container { println containerMap; println stepNumber; containerMap.get(stepNumber++) }

    maxForks 1

    input:
    path(jsonFile, stageAs: "step_json_file.json")
    path(remainingStepsFile, stageAs: "input_remaining_steps.json")
    path mainWorkingDirectory
    val stepNumber
    val containerMap

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

    def stepNumber = 1; // this will be incremented by the recursion

    def containerMap = [:]

    def slurper = new XmlSlurper();
    def parsedXml = slurper.parseText(file(params.analysisConfigFile).text)

    if(parsedXml.step.size() < 1) {
        throw new Exception("XML file must containe at least one step")
    }

    for (int i = 0; i < parsedXml.step.size(); i++) {
        def xmlStep = parsedXml.step[i];
        def containerName = 'veupathdb/gusenv:latest';

        // notice the fancy syntax to get the attribute value
        if(xmlStep.@class == "ApiCommonData::Load::IterativeWGCNAResults") {
            containerName = 'veupathdb/iterativewgcna:latest'
        }
        def key = i + 1;
        containerMap.put(key, containerName)
    }

    analysisConfigXml = Channel.fromPath(params.analysisConfigFile, checkIfExists: true)

    MAIN_WORKING_DIRECTORY(params.finalDir, params.tpmDir).collect()

    stepsJson = PARSE_XML_CONFIG(
        analysisConfigXml
    ).collect()

    ANALYZE_STEPS
        .recurse(stepsJson, MAIN_WORKING_DIRECTORY.out, stepNumber, containerMap)
        .times(parsedXml.step.size())
}


workflow ANALYZE_STEPS {
    take:
    stepsJson
    mainWorkingDirectory
    stepNumber
    containerMap
    
    main:
    stepConfig = NEXT_STEP(stepsJson)

    DO_STEP(stepConfig, mainWorkingDirectory, stepNumber, containerMap)

    emit:
    DO_STEP.out.remainingSteps
    DO_STEP.out.mainWorkingDirectory
    DO_STEP.out.stepNumber
    containerMap
}


