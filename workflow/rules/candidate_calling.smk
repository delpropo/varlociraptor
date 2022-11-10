rule freebayes:
    input:
        ref=genome,
        ref_idx=genome_fai,
        #regions="results/regions/{group}.target_regions.filtered.bed",
        # you can have a list of samples here
        samples=lambda w: get_group_crams(w),
        indexes=lambda w: get_group_crams(w, bai=True),
    output:
        pipe("results/candidate-calls/{group}.freebayes.raw.bcf")
    log:
        "logs/freebayes/{group}.log",
    params:
        # genotyping is performed by varlociraptor, hence we deactivate it in freebayes by 
        # always setting --pooled-continuous
        extra="--pooled-continuous --min-alternate-count {} --min-alternate-fraction {}".format(
            1 if is_activated("calc_consensus_reads") else 2,
            config["params"]["freebayes"].get("min_alternate_fraction", "0.05"),
        ),
        chunksize=10000000,
    threads: max(workflow.cores - 1, 1)  # use all available cores -1 (because of the pipe) for calling
    wrapper:
        "v1.10.0/bio/freebayes"


rule freebayes_quality_filter:
    input:
        "results/candidate-calls/{group}.freebayes.raw.bcf",
    output:
        "results/candidate-calls/{group}.freebayes.bcf",
    conda:
        "../envs/bcftools.yaml"
    shell:
        "bcftools view  -i'QUAL>1' {input} -Ob > {output}"


rule delly:
    input:
        ref=genome,
        ref_idx=genome_fai,
        alns=lambda w: get_group_crams(w),
        index=lambda w: get_group_crams(w, bai=True),
        exclude="results/regions/{group}.excluded_regions.bed",
    output:
        "results/candidate-calls/{group}.delly.bcf",
    log:
        "logs/delly/{group}.log",
    params:
        extra=config["params"].get("delly", ""),
    threads: lambda _, input: len(input.alns)  # delly parallelizes over the number of samples
    wrapper:
        "v1.10.0/bio/delly"


# Delly breakends lead to invalid BCFs after VEP annotation (invalid RLEN). Therefore we exclude them for now.
rule fix_delly_calls:
    input:
        "results/candidate-calls/{group}.delly.bcf",
    output:
        "results/candidate-calls/{group}.delly.no_bnds.bcf",
    log:
        "logs/fix_delly_calls/{group}.log",
    conda:
        "../envs/bcftools.yaml"
    shell:
        """bcftools view -e 'INFO/SVTYPE="BND"' {input} -Ob > {output} 2> {log}"""


rule scatter_candidates:
    input:
        get_fixed_candidate_calls,
    output:
        scatter.calling(
            "results/candidate-calls/{{group}}.{{caller}}.{scatteritem}.bcf"
        ),
    log:
        "logs/scatter-candidates/{group}.{caller}.log",
    conda:
        "../envs/rbt.yaml"
    shell:
        "rbt vcf-split {input} {output}"
