process REPORTSUMM {
        time '5min'
        tag "Summarizing..."
        publishDir "${baseDir}/Reports/${params.batch}", mode: 'copy'
        container = "docker://nfcore/methylseq"
        input:
        path '*'

        output:
        path "*.html", emit: html
        path "*.txt", emit: reports
        script:
        """
        bismark2report
        bismark2summary
        """
}