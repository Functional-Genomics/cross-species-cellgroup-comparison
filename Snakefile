configfile: "config.yaml"

IN_DIR='inputs'
OUT_DIR='output'

EXPS=[config.get("exp1").get('id'), config.get("exp2").get("id")]

rule all:
    input:
        dynamic("%s/%s_vs_%s.{organism_part}.tsv" % (OUT_DIR, config.get('exp1').get('id'), config.get('exp2').get('id')))     

rule extract_metadata:
    conda:
         'envs/scanpy-scripts.yml'

    input:
        anndata = "%s/{exp}.project.h5ad" % IN_DIR

    output:
        meta = temp("{outdir}/meta/{exp}.tsv")

    shell:
        """
        scripts/extract_meta.py {input.anndata} {output.meta}        
        """

rule intersect_metadatas:
    conda:
         'envs/ontology_index.yml'
    
    input:
        metas = expand("{{outdir}}/meta/{exp}.tsv", exp = EXPS),
        ontology_file="%s/%s" % (IN_DIR, config.get('ontology_file'))
    
    output:
        temp(dynamic(expand("{{outdir}}/meta_subs/{exp}.{{organism_part}}.tsv", exp=EXPS)))

    shell:
        """
        bin/compare_terms.R {input.ontology_file} {input.metas[0]} {input.metas[1]} \
            organism_part_ontology organism_part {OUT_DIR}/meta_subs
        """

rule subset_data_toparts:
    conda:
         'envs/scanpy-scripts.yml'
    
    input:
        adata="%s/{exp}.project.h5ad" % IN_DIR,
        sub="{outdir}/meta_subs/{exp}.{organism_part}.tsv"        

    output:
        adata_sub=temp("{outdir}/adata_subs/{exp}.{organism_part}.h5ad")

    shell:
        """
        scripts/subset_anndata.py {input.adata} {input.sub} {output.adata_sub}
        """

rule filter_cells:
    conda:
         'envs/scanpy-scripts.yml'
    
    input:
        adata_sub="{outdir}/adata_subs/{exp}.{organism_part}.h5ad"

    output:
        adata=temp("{outdir}/markers/{exp}.{organism_part}.cellfiltered.h5ad")

    shell:
        """
        scanpy-filter-cells --gene-name 'gene_symbols' --param 'c:n_genes' 400.0 \
            1000000000.0 --param 'c:n_counts' 0.0 1000000000.0  --input-format 'anndata' \
            {input.adata_sub}  --show-obj stdout --output-format anndata {output.adata}
        """
        
rule filter_genes:
    conda:
         'envs/scanpy-scripts.yml'
    
    input:
        adata="{outdir}/markers/{exp}.{organism_part}.cellfiltered.h5ad"

    output:
        adata=temp("{outdir}/markers/{exp}.{organism_part}.genefiltered.h5ad")

    shell:
        """
        scanpy-filter-genes --param 'g:n_cells' 3.0 1000000000.0 --input-format 'anndata' \
            {input.adata}  --show-obj stdout --output-format anndata {output.adata}
        """


rule normalise:
    conda:
         'envs/scanpy-scripts.yml'
    
    input:
        adata="{outdir}/markers/{exp}.{organism_part}.genefiltered.h5ad"

    output:
        adata=temp("{outdir}/markers/{exp}.{organism_part}.normalised.h5ad")

    shell:
        """
        scanpy-normalise-data --normalize-to '10000.0' --save-raw yes \
            --input-format 'anndata' {input.adata}  --show-obj stdout --output-format anndata \
            {output.adata}
        """

rule rgg:
    conda:
         'envs/scanpy-scripts.yml'
    
    input:
        adata="{outdir}/markers/{exp}.{organism_part}.normalised.h5ad"

    output:
        adata=temp("{outdir}/markers/{exp}.{organism_part}.markers.h5ad"),
        tsv=temp("{outdir}/markers/{exp}.{organism_part}.markers.tsv")

    params:
        cell_type_field = config.get('cell_type_field')        

    shell:
        """
        scanpy-find-markers --save "{output.tsv}" --n-genes '100' --groupby \
            '{params.cell_type_field}' --key-added 'markers_{params.cell_type_field}' --method \
            't-test_overestim_var' --use-raw --reference 'rest' --filter-params \
            'min_in_group_fraction:0.0,max_out_group_fraction:1.0,min_fold_change:1.0' \
            --input-format 'anndata' {input.adata} --show-obj stdout --output-format \
            anndata {output.adata}
        """

rule compare_experiments:
    input:
        exp1="{outdir}/markers/{exp1}.{organism_part}.markers.tsv",
        exp2="{outdir}/markers/{exp2}.{organism_part}.markers.tsv",
        ortholog_mapping_file="%s/%s" % (IN_DIR, config.get('ortholog_mapping_file'))

    output:
        comp="{outdir}/{exp1}_vs_{exp2}.{organism_part}.tsv"     
    
    params:
        species1=config.get('exp1').get('species'),
        species2=config.get('exp2').get('species'),
        min_overlap=config.get('compare_experiments').get('min_overlap'),
        pval_limit=config.get('compare_experiments').get('pval_limit')

    shell:
        """
        bin/compare_experiments.R {input.exp1} {params.species1} {input.exp2} \
            {params.species2} {input.ortholog_mapping_file} {params.pval_limit} \
            {params.min_overlap} {output.comp}
        """




