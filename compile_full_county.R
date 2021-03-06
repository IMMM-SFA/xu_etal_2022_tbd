## copied in from CityBES/LA/data-raw/
## modified filepath to suit the current folder setting, added some comments
## data files will be ignored and uploaded
## fixme: run through and verify

library("dplyr")
library("tibble")

## set work folder to be inside "code"
setwd("code")

## had some parsing failure in HouseFraction. This column is not used, so should be fine
df = readr::read_csv("input_data/Assessor_Parcels_Data_-_2019.csv")

df %>%
  dplyr::mutate_if(is.character, as.factor) %>%
  summary()

df.select.col <- df %>%
  dplyr::select(AssessorID, GeneralUseType, SpecificUseType, SQFTmain, YearBuilt, EffectiveYearBuilt, CENTER_LAT, CENTER_LON) %>%
  {.}

df.select.col %>%
  readr::write_csv("intermediate_data/Assessor_Parcels_Data_-_2019_col_subset.csv")

## can load this smaller data file when not run the first time
## df.select.col <- readr::read_csv("intermediate_data/Assessor_Parcels_Data_-_2019_col_subset.csv")

df.select.col %>%
  summary()

## invalid building size
df.select.col %>%
  dplyr::filter(SQFTmain == 0) %>%
  {.}

## invalid built year
df.select.col %>%
  dplyr::filter(EffectiveYearBuilt == 0) %>%
  {.}

df.select.col.geo <- df.select.col %>%
  dplyr::filter(!is.na(CENTER_LON)) %>%
  sf::st_as_sf(coords=c("CENTER_LON", "CENTER_LAT"), crs=4326)

df.geo <- sf::st_read("../input_data/LARIAC6_LA_County.geojson")

df.geo %>%
  nrow()

df.geo.nogeom <- df.geo

sf::st_geometry(df.geo.nogeom) <- NULL

df.geo.nogeom %>%
  dplyr::mutate_if(is.character, as.factor) %>%
  summary()

df.geo.nogeom %>%
  dplyr::filter(BLD_ID == 201404851590000)

df.geo.valid <- sf::st_make_valid(df.geo)

## [329812] Loop 0 is not valid: Edge 10 crosses edge 13.
df.geo.valid.round2 <- sf::st_make_valid(df.geo.valid %>% dplyr::slice(329812))

df.select.col.geo.valid <- sf::st_make_valid(df.select.col.geo)

df.join <- sf::st_join(df.geo.valid %>%
                       dplyr::slice(1:329811, 329813:3293177),
                       df.select.col.geo.valid, join=sf::st_contains)

head(df.join)

df.join.nogeom <- df.join

sf::st_geometry(df.join.nogeom) <- NULL

df.join.nogeom.sel.col <- df.join.nogeom %>%
  dplyr::select(OBJECTID, HEIGHT, Shape_Area, AssessorID:EffectiveYearBuilt) %>%
  dplyr::filter(!is.na(AssessorID)) %>%
  tibble::as_tibble() %>%
  {.}

df.join.nogeom.sel.col %>%
  ## dplyr::distinct(OBJECTID)
  dplyr::distinct(AssessorID)

df.join.nogeom.sel.col %>%
  dplyr::group_by(OBJECTID) %>%
  dplyr::filter(n()>1) %>%
  dplyr::ungroup() %>%
  dplyr::distinct(OBJECTID)

df.join.nogeom.sel.col %>%
  dplyr::group_by(AssessorID) %>%
  dplyr::filter(n()>1) %>%
  dplyr::ungroup() %>%
  dplyr::distinct(AssessorID)

join.unique <- df.join.nogeom.sel.col %>%
  dplyr::group_by(OBJECTID) %>%
  dplyr::filter(n() == 1) %>%
  dplyr::ungroup() %>%
  dplyr::group_by(AssessorID) %>%
  dplyr::filter(n() == 1) %>%
  dplyr::ungroup() %>%
  {.}

df.join.nogeom.sel.col.one.many <- df.join.nogeom.sel.col %>%
  dplyr::group_by(OBJECTID) %>%
  dplyr::filter(n()>1) %>%
  dplyr::ungroup()

df.join.nogeom.sel.col.one.many %>%
  distinct(OBJECTID)

df.join.nogeom.sel.col.one.many.clean <-
  df.join.nogeom.sel.col.one.many %>%
  dplyr::filter(EffectiveYearBuilt > 0) %>%
  dplyr::filter(SQFTmain > 0) %>%
  {.}

df.one.many.nontype <- df.join.nogeom.sel.col.one.many.clean %>%
  dplyr::group_by(OBJECTID) %>%
  dplyr::summarise(HEIGHT = mean(HEIGHT),
                   EffectiveYearBuilt = max(EffectiveYearBuilt ),
                   SQFTmain = mean(SQFTmain)) %>%
  dplyr::ungroup() %>%
  {.}

set.seed(0)

df.one.many.type.count <- df.join.nogeom.sel.col.one.many.clean %>%
  dplyr::group_by(OBJECTID, GeneralUseType, SpecificUseType) %>%
  dplyr::summarise(count = n()) %>%
  dplyr::ungroup() %>%
  {.}

## select the most common type
df.one.many.type.count.majority <- df.one.many.type.count %>%
  dplyr::group_by(OBJECTID) %>%
  dplyr::filter(length(unique(count)) > 1) %>%
  dplyr::ungroup() %>%
  dplyr::arrange(OBJECTID, desc(count)) %>%
  dplyr::group_by(OBJECTID) %>%
  dplyr::slice(1) %>%
  dplyr::ungroup() %>%
  {.}

## if all the same frequency, select a random one
df.one.many.type.count.random <- df.one.many.type.count %>%
  dplyr::group_by(OBJECTID) %>%
  dplyr::filter(length(unique(count)) == 1) %>%
  dplyr::ungroup() %>%
  dplyr::group_by(OBJECTID) %>%
  dplyr::sample_n(size = 1) %>%
  dplyr::ungroup() %>%
  {.}

df.one.many.type <- df.one.many.type.count.majority %>%
  dplyr::bind_rows(df.one.many.type.count.random) %>%
  dplyr::select(-count)

df.one.many.clean <- df.one.many.nontype %>%
  dplyr::left_join(df.one.many.type, by="OBJECTID")

df.clean <- join.unique %>%
  dplyr::select(OBJECTID, HEIGHT, EffectiveYearBuilt, SQFTmain, GeneralUseType, SpecificUseType) %>%
  dplyr::bind_rows(df.one.many.clean) %>%
  dplyr::filter(EffectiveYearBuilt > 0) %>%
  dplyr::filter(SQFTmain > 0) %>%
  {.}

df.clean %>%
  dplyr::mutate_at(vars(OBJECTID, GeneralUseType, SpecificUseType), as.factor) %>%
  summary() %>%
  {.}

df.clean %>%
  dplyr::group_by(GeneralUseType, SpecificUseType) %>%
  dplyr::summarise(count = n()) %>%
  dplyr::ungroup() %>%
  readr::write_csv("intermediate_data/building_type_count.csv")

## join df.clean with building geometry or centroid

df.type.recode = readr::read_csv("building_type_recode.csv") %>%
  dplyr::mutate(`remap EP ref building` = ifelse(is.na(`remap EP ref building`), SpecificUseType, `remap EP ref building`)) %>%
  {.}

df.geo.compile <- df.geo %>%
  dplyr::select(OBJECTID) %>%
  dplyr::inner_join(df.clean, by="OBJECTID") %>%
  dplyr::left_join(df.type.recode, by=c("GeneralUseType", "SpecificUseType")) %>%
  {.}

df.geo.compile %>%
  sf::st_write("output_data/compiled_LA_building.geojson")
