-- One row per raw customer record (duplicates are NOT removed here; see
-- int_customers_deduplicated). Cleans text and types; keeps lineage columns.
with source as (

    select * from {{ source('bronze', 'raw_customers') }}

),

cleaned as (

    select
        try_to_number(_record_id)                         as source_record_id,
        upper(trim(customer_id))                          as customer_id,
        -- INITCAP with explicit delimiters: by default Snowflake does not treat
        -- an apostrophe as a word boundary ("O'Brien" would become "O'brien").
        initcap(nullif(trim(first_name), ''), ' ''-')     as first_name,
        initcap(nullif(trim(last_name), ''), ' ''-')      as last_name,
        lower(nullif(trim(email), ''))                    as email,
        nullif(trim(phone), '')                           as phone,
        upper(nullif(trim(country_code), ''))             as country_code,
        try_to_date(trim(signup_date), 'YYYY-MM-DD')      as signup_date,
        try_to_timestamp_ntz(trim(updated_at), 'YYYY-MM-DD HH24:MI:SS') as source_updated_at,
        _source_file                                      as source_file,
        try_to_timestamp_tz(_extracted_at)                as source_extracted_at
    from source

)

select * from cleaned
