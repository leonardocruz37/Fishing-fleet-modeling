library(embarcadero)
library(fuzzySim)

##  CLEAR EVERYTHING
rm(list = ls(all.names = TRUE))

set.seed(2024)

path <- "~/Project Fishing Fleet Modeling"

# Raster data
setwd(paste0(path, "/environmental variables/present/"))
var_stack <- stack(list.files(".", full.names = TRUE, pattern = '.nc'))
var_stack <- raster::aggregate(var_stack, 1/res(var_stack))

setwd(paste0(path, "/environmental variables/ssp4_2100/"))
var_stack_f85 <- stack(list.files(".", full.names = TRUE, pattern = '.nc'))
var_stack_f85 <- raster::aggregate(var_stack_f85, 1/res(var_stack_f85))

setwd(paste0(path, "/environmental variables/ssp1_2100/"))
var_stack_f26 <- stack(list.files(".", full.names = TRUE, pattern = '.nc'))
var_stack_f26 <- raster::aggregate(var_stack_f26, 1/res(var_stack_f26))
setwd(path)

# MMSI data
dat.all <- read.csv(paste0(path,'/data/mmsi_2013-2020_processed.csv')) %>%
  left_join(read.csv(paste0(path,'/data/metadata.csv'))[,c(1,4,8)], by = 'mmsi') %>%
  filter(vessel_class_gfw != 'fishing') %>%
  na.omit()

vessel_classes <- sort(unique(dat.all$vessel_class_gfw))
list <- c('Global',vessel_classes)

varimp_df <- list()
for(do in list){
  if(do == 'Global'){
    ifelse(!dir.exists(file.path(paste0(path,'/output/'), do)), dir.create(file.path(paste0(path,'/output/'), do)), FALSE)
    do_path <- paste0(path,'/output/', do)
    
    dat.presence <- dat.all %>%
      select(cell_ll_lon,cell_ll_lat) %>%
      setNames(., c('x','y')) %>%
      distinct()
    
    dat <- fuzzySim::gridRecords(var_stack, dat.presence)
    dat <- dat[complete.cases(dat),]
  }
  
  if(do %in% vessel_classes){
    ifelse(!dir.exists(file.path(paste0(path,'/output/fishing gears/'), do)), dir.create(file.path(paste0(path,'/output/fishing gears/'), do)), FALSE)
    do_path <- paste0(path,'/output/fishing gears/', do)
    
    dat.presence <- dat.all %>%
      filter(vessel_class_gfw == do) %>%
      select(cell_ll_lon,cell_ll_lat) %>%
      setNames(., c('x','y')) %>%
      distinct()
    
    dat <- fuzzySim::gridRecords(var_stack, dat.presence)
    dat <- dat[complete.cases(dat),]
  }
  
  #Input data
  names(dat)
  spc_col <- 1 # presence (1) - absence (0) column
  var_cols <- 5:12 # predictor variable columns
  names(dat)[spc_col]
  names(dat)[var_cols]
  myspecies <- names(dat)[spc_col]
  myspecies
  
  #Modeling
  mod_BART <- bart(x.train = dat[ , var_cols], y.train = dat[ , myspecies], keeptrees = TRUE)
  
  # Save summary
  sink(paste0(do_path, '/Table 1. BART summary (', do,').txt'), type = 'output')
  print(summary(mod_BART))
  sink()
  
  #Save the diagnostic plot
  ggsave(paste0(path, '/diagnostic plots/',do,'.png'), width = 7,height = 5)
  
  # Variable importance
  varimp_plot <- varimp(mod_BART, plots = TRUE)
  varimp_plot$class <- do
  varimp_df <- rbind(varimp_df, varimp_plot)
  
  # Raster predictions
  BART_P <- as.data.frame(predict2.bart(mod_BART, var_stack, quantiles=c(0.025, 0.975)),xy=TRUE)
  BART_F85 <- as.data.frame(predict2.bart(mod_BART, var_stack_f85, quantiles=c(0.025, 0.975)),xy=TRUE)
  BART_F26 <- as.data.frame(predict2.bart(mod_BART, var_stack_f26, quantiles=c(0.025, 0.975)),xy=TRUE)
  
  # 'layer' is the posterior mean
  colnames(BART_P) <- c('x','y','layer','lower_95_ci','upper_95_ci')
  colnames(BART_F85) <- c('x','y','layer','lower_95_ci','upper_95_ci')
  colnames(BART_F26) <- c('x','y','layer','lower_95_ci','upper_95_ci')
  
  # Difference
  BART_DIFF85 <- data.frame(x=BART_P[,1],
                            y=BART_P[,2],
                            layer = BART_F85[,3] - BART_P[,3],
                            lower_95_ci = BART_F85[,4] - BART_P[,4],
                            upper_95_ci = BART_F85[,5] - BART_P[,5])
  
  BART_DIFF26 <- data.frame(x=BART_P[,1],
                            y=BART_P[,2],
                            layer=BART_F26[,3] - BART_P[,3],
                            lower_95_ci = BART_F26[,4] - BART_P[,4],
                            upper_95_ci = BART_F26[,5] - BART_P[,5])
  
  # Save predictions
  write.csv(BART_P, paste0(do_path,'/BART_P (',do,').csv'),row.names=FALSE)
  write.csv(BART_F85, paste0(do_path,'/BART_F85 (',do,').csv'),row.names=FALSE)
  write.csv(BART_F26, paste0(do_path,'/BART_F26 (',do,').csv'),row.names=FALSE)
  
  write.csv(BART_DIFF85, paste0(do_path,'/BART_DIFF85 (',do,').csv'),row.names=FALSE)
  write.csv(BART_DIFF26, paste0(do_path,'/BART_DIFF26 (',do,').csv'),row.names=FALSE)
  
  # Presence points based on model threshold
  threshold <- summary(mod_BART)[[3]][["plot_env"]][["thresh"]]
  write.csv(BART_P %>% filter(layer >= threshold), paste0(do_path,'/BART_P_presence (',do,').csv'),row.names=FALSE)
  write.csv(BART_F85 %>% filter(layer >= threshold), paste0(do_path,'/BART_F85_presence (',do,').csv'),row.names=FALSE)
  write.csv(BART_F26 %>% filter(layer >= threshold), paste0(do_path,'/BART_F26_presence (',do,').csv'),row.names=FALSE)
  
  # Delete model to free memory space
  rm(mod_BART)
  
}

write.csv(varimp_df, paste0(path,'/output/variable_importance_gear_global.csv'), row.names = FALSE)