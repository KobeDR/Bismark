nextflow.enable.dsl=2
genbuild = params.genbuild
if (params.protocol == 'EMseq'){
        params.bismark_index="/staging/leuven/stg_00064/Kobe_2/db/reference/hg38/EMseq"
        params.genbuild = 'hg38'
} else if (genbuild == 'mm39'){
        params.bismark_index = "/staging/leuven/stg_00064/Kobe_2/db/reference/mm39"

} else if (genbuild == 'hg19'){
        params.bismark_index="/staging/leuven/stg_00064/Kobe_2/db/reference/hg19/hs37d5"

} else if (genbuild == 'hg38'){
        params.bismark_index="/staging/leuven/stg_00064/Kobe_2/db/reference/hg38/broad"

}
scripts = "${baseDir}/Scripts"
thisf = "${baseDir}"

params.reads="${params.workingDir}/*${params.pattern}{1,2}*.gz"
reads=Channel.fromFilePairs(params.reads)
workingDir="${params.workingDir}"
bismark_index=Channel.fromPath(params.bismark_index)
params.all_reads="${params.workingDir}/*R*.gz"
all_reads=Channel.fromPath(params.reads)
if (params.regions !=''){
regions = Channel.fromPath(params.regions)
}
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
include { BISMARK_ALIGN   } from './Processes/Align.nf'
include { COMPUTE_ON_TARGET   } from './Processes/Compute_on_target.nf'
include { DEDUPLICATE   } from './Processes/Deduplicate.nf'
include { FASTQ_SCREEN } from './Processes/FastQ_screen.nf'
include { FASTQC } from './Processes/FastQC.nf'
include { EXTRACT } from './Processes/Methylation_extract.nf'
include { MULTIFASTQC } from './Processes/MultifastQC.nf'
include { REPORTSUMM } from './Processes/ReportSummary.nf'
include { SORT } from './Processes/Sort.nf'
include { SORT_AND_INDEX } from './Processes/Sort.nf'

include { TRIM } from './Processes/Trim_galore.nf'
include { GET_PUC_LAMBDA } from './Processes/Get_puc_lambda.nf'
if(params.regions==''){
        include { COMBINE_METADATA } from './Processes/Combine_metadata.nf'
} else {
       include { COMBINE_METADATA_REGIONS as COMBINE_METADATA } from './Processes/Combine_metadata.nf' 
}
include { REGIONAL_SUBSET } from './Processes/Subset_regions.nf'
include { REGIONAL_SUBSET_DUPLICATED } from './Processes/Subset_regions.nf'
include { DUPLICATION_ON_TARGET } from './Processes/Subset_regions.nf'

include { REGIONAL_READS } from './Processes/Compute_regional_reads.nf'
include { DEPTH_OF_COVERAGE } from './Processes/Compute_regional_coverage.nf'
include { COMBINE_MEAN_REGIONAL_COVERAGES } from './Processes/Combine_coverages.nf'
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
        // Comment out next step or provide your own working image in the FastQ_screen.nf file
        if(params.fastq_s == 'on'){
        FASTQ_SCREEN(trim_ch)
        }
        BISMARK_ALIGN(params.bismark_index, trim_ch)
        align_ch=BISMARK_ALIGN.out.bam_files
        align_bams_ch = BISMARK_ALIGN.out.only_bam_files
        align_report_ch=BISMARK_ALIGN.out.reports
        sort_ch = SORT(align_ch)
        DEDUPLICATE(sort_ch)
        deduplicate_ch=DEDUPLICATE.out.bam_files
        sort_and_indexed_ch = SORT_AND_INDEX(deduplicate_ch)

        deduplicate_ch2=DEDUPLICATE.out.bam_file2
        puc_lambda_ch = GET_PUC_LAMBDA(deduplicate_ch2.collect(), scripts)
        deduplicate_report_ch=DEDUPLICATE.out.reports
        if(params.regions != ''){
        on_targ_ch=COMPUTE_ON_TARGET(params.regions, align_bams_ch.collect(), scripts)
        REGIONAL_SUBSET(params.regions, deduplicate_ch)
        subs_ch = REGIONAL_SUBSET.out.reg_sub
        subs_only_bams = REGIONAL_SUBSET.out.only_bam_files
        subs2_ch = REGIONAL_SUBSET_DUPLICATED(params.regions, align_ch)
        subs2_ch = subs2_ch.join(subs_ch)
        DUPLICATION_ON_TARGET(subs2_ch)
        doc_ch = DEPTH_OF_COVERAGE(params.regions, subs_ch, params.bismark_index)
        reg_reads_ch = REGIONAL_READS(subs_only_bams.collect())
        comb_cov_ch = COMBINE_MEAN_REGIONAL_COVERAGES(doc_ch.collect(), scripts)
        }
        EXTRACT(deduplicate_ch)
        extract_coverages_ch = EXTRACT.out.coverages
        extract_report_ch = EXTRACT.out.reports
        reports_ch=extract_report_ch
        reports_ch=reports_ch.mix(align_report_ch, deduplicate_report_ch, align_bams_ch, deduplicate_ch2)
        reports_ch.view()
        REPORTSUMM(reports_ch.collect())
        total_report_ch = REPORTSUMM.out.reports
        if(params.regions != ''){
        COMBINE_METADATA(extract_coverages_ch.collect(), puc_lambda_ch, total_report_ch, scripts,on_targ_ch, reg_reads_ch, comb_cov_ch)
        } else {
        COMBINE_METADATA(extract_coverages_ch.collect(), puc_lambda_ch, total_report_ch, scripts)
        }

}

workflow.onComplete {
        log.info (workflow.success? "Done! View the summary report in the ${baseDir}/Results/Reports/${params.batch} folder!" : "Oops... something went wrong")
}