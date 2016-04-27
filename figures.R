# Plot theme
partial_plot_theme <- function(legend.position = "none", strips = FALSE,...) {
  sb <- if(strips==TRUE) element_rect(fill='lightgrey') else element_blank()
  st <- if(strips==TRUE) element_text(face='italic') else element_blank()
  theme_classic(base_size = 7) + theme(strip.text = st,
                          legend.title = element_blank(),
                          strip.background = sb,
                          legend.position = legend.position,
                          axis.line.x = element_line(colour = 'black', size=0.5, linetype='solid'),
                          axis.line.y = element_line(colour = 'black', size=0.5, linetype='solid'),
                          plot.margin = unit(c(3,3,3,3), "mm"))
}

# Plot log likelhoods for each model
plot_loglik <- function(loglik_summary) {
  dat <- loglik_summary %>%
  mutate(model = factor(comparison, levels=c("without_random_effects","with_random_effects"))) %>%
  mutate(model = factor(comparison, labels = c( "model","model + species effects"))) %>%
  arrange(comparison)
  
  ggplot(dat, aes(x = model,y = mean)) + 
  geom_pointrange(aes(ymin = `2.5%`, ymax=`97.5%`), position=position_dodge(.1), size=0.2) +
  ylab('Log likelihood') + 
  xlab('Model') +
  ylim(0,500),
  partial_plot_theme()
}