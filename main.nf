#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

import groovy.json.JsonSlurper;

process PARSE_XML_CONFIG {
    container 'veupathdb/bioperl:latest'

    input:
    path xml_file

    output:
    path "step_*.json", emit: step_queue

    script:
    """
    #!/usr/bin/perl
    use CBIL::StudyAssayResults::XmlParser;
    my \$xmlParser = CBIL::StudyAssayResults::XmlParser->new("$xml_file");
    \$xmlParser->printToJsonFiles();
    """
}


process MAIN_WORKING_DIRECTORY {
    container 'veupathdb/alpine_bash:latest'

    output:
    path "main_working_directory"

    script:
    """
    mkdir main_working_directory
    """
}

process DO_STEP {
    container { containerName}

    maxForks 1

    input:
    tuple val(containerName), path(stepFile)
    path mainWorkingDir


    output:
    path "main_working_directory"

    script:
    """
    echo test
    """

}




workflow {
    
    xml_file_ch = Channel.fromPath(params.xml_file, checkIfExists: true)

    MAIN_WORKING_DIRECTORY()

    PARSE_XML_CONFIG(
        xml_file_ch
    )

    // this operation assures we have an ordered list of steps.  The output is a FIFO channel
    ordered_files = PARSE_XML_CONFIG.out.step_queue
        .flatten()
        .map { file -> [ file, (file.name =~ /step_(\d+)\.json/)[0][1] as int ] }
        .toSortedList { a, b -> a[1] <=> b[1] }
        .flatten()
        .filter( ~/.*json/ ) 
        .map { step_file ->
            def jsonSlurper = new JsonSlurper()
            def jsonData = jsonSlurper.parse(step_file)

            def dynamicContainer = 'veupathdb/gusenv:latest';
            if(jsonData.class == "ApiCommonData::Load::IterativeWGCNAResults") {
                dynamicContainer = 'veupathdb/iterativewgcna:latest'
            }
            return [dynamicContainer, step_file]
        }

    ordered_files.view()
    
    DO_STEP(ordered_files, MAIN_WORKING_DIRECTORY.out)
    
}
