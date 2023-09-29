nextflow.enable.dsl=2
genbuild = params.genbuild
if (genbuild == 'mm39'){
        params.bismark_index = "/staging/leuven/stg_00064/Kobe_2/db/reference/mm39"

} else if (genbuild == 'hg19'){
        params.bismark_index="/staging/leuven/stg_00064/Kobe_2/db/reference/hg19/hs37d5"

} else if (genbuild == 'hg38'){
        params.bismark_index="/staging/leuven/stg_00064/Kobe_2/db/reference/hg38/broad"

}
params.reads="${params.workingDir}/*${params.pattern}{1,2}*.gz"
reads=Channel.fromFilePairs(params.reads)
workingDir="${params.workingDir}"
bismark_index=Channel.fromPath(params.bismark_index)
params.all_reads="${params.workingDir}/*R*.gz"
all_reads=Channel.fromPath(params.reads)
regions = Channel.fromPath(params.regions)

if (params.protocol == 'bsseq'){
    params.min_reads=20
    params.samtools_filter='-F 4 -F 256 -q 30'
    params.bismark_align='-N 1 -L 20'
    params.clip_R1=10
    params.clip_R2=27
    params.three_prime_clip_R1=10
    params.three_prime_clip_R2=10
} else if (params.protocol == 'EMseq'){
    params.min_reads=20
    params.samtools_filter='-F 4 -F 256 -q 30'
    params.bismark_align='-N 1 -L 20'
    params.clip_R1=10
    params.clip_R2=7
    params.three_prime_clip_R1=15
    params.three_prime_clip_R2=13
}
include { BISMARK_ALIGN   } from './Align.nf'
include { COMPUTE_ON_TARGET   } from './Compute_on_target.nf'
include { DEDUPLICATE   } from './Deduplicate.nf'
include { FASTQ_SCREEN } from './FastQ_screen.nf'
include { FASTQC } from './FastQC.nf'
include { EXTRACT } from './Methylation_extract.nf'
include { MULTIFASTQC } from './MultifastQC.nf'
include { REPORTSUMM } from './ReportSummary.nf'
include { SORT } from './Sort.nf'
include { TRIM } from './Trim_galore.nf'

log.info """\
    B I S M A R K  A L I G N  P I P E L I N E
    ==========================================
    reference    : ${params.bismark_index}
    reads        : ${params.reads}
    """
    .stripIndent()

workflow {
        FASTQC(all_reads)
        html_ch=FASTQC.out.htmls
        zip_ch=FASTQC.out.zips
        MULTIFASTQC(html_ch.mix(zip_ch).collect())
        trim_ch = TRIM(reads)
        FASTQ_SCREEN(trim_ch)
        BISMARK_ALIGN(params.bismark_index, trim_ch)
        align_ch=BISMARK_ALIGN.out.bam_files
        align_report_ch=BISMARK_ALIGN.out.reports
        sort_ch = SORT(align_ch)
        DEDUPLICATE(sort_ch)
        deduplicate_ch=DEDUPLICATE.out.bam_files
        deduplicate_report_ch=DEDUPLICATE.out.reports
        if(regions != ''){
        on_targ_ch=COMPUTE_ON_TARGET(params.regions, align_ch.collect())
        }
        EXTRACT(deduplicate_ch)
        extract_coverages_ch = EXTRACT.out.coverages
        extract_report_ch = EXTRACT.out.reports
        reports_ch=extract_report_ch
        reports_ch=reports_ch.mix(align_report_ch, deduplicate_report_ch, align_ch, deduplicate_ch)

        REPORTSUMM(reports_ch.collect())
}

workflow.onComplete {
        log.info (workflow.success? "Done! View the summary report in the ${baseDir}/Reports folder!" : "Oops... something went wrong")
}