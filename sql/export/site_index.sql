-- site_index: the list of report weeks the live page can open, newest first.
-- Built from the week files on disk, so it always matches the archive.
-- export_site_data() fills {{dir}}.

COPY (
    SELECT list({season: season, week: week, focal_team: focal_team,
                 focal_opponent: focal_opponent,
                 file: regexp_extract(filename, '[^/\\]+$')}
                ORDER BY season DESC, week DESC) AS weeks
    FROM read_json('{{dir}}/[0-9][0-9][0-9][0-9]-week[0-9][0-9].json',
                   filename = true, maximum_object_size = 67108864)
) TO '{{dir}}/index.json' (FORMAT JSON);
