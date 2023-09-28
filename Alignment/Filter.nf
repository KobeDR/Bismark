process FILTER {
        tag "Filtering reads..."
        publishDir "${baseDir}/Cache/Alignment/Filtered"
        container = "docker://biocontainers/samtools"
        input:
        path bam_file

        output:
        path "${bam_file}"

        script:
        """
        samtools view -bS -@ ${task.cpus} ${params.samtools_filter} $bam_file > tmp
        mv tmp $bam_file
        """


}