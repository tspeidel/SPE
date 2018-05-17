## Source: https://rud.is/b/2016/03/26/nuclear-animations-in-r/

library(purrr)
library(dplyr)
library(tidyr)
library(sp)
library(maptools)
library(maps)
library(grid)
library(scales)
library(ggplot2)   # devtools::install_github("hadley/ggplot2")
library(ggthemes)
library(gridExtra)
library(ggalt)



# read and munge the data, being kind to github's servers
URL <- "https://raw.githubusercontent.com/data-is-plural/nuclear-explosions/master/data/sipri-report-explosions.csv"
fil <- basename(URL)
if (!file.exists(fil)) download.file(URL, fil)

read.csv(fil, stringsAsFactors=FALSE) %>%
     tbl_df() %>%
     mutate(date=as.Date(as.character(date_long), format="%Y%m%d"),
            year=as.character(year),
            yr=as.Date(sprintf("%s-01-01", year)),
            country=sub("^PAKIST$", "PAKISTAN", country)) -> dat

# doing this so we can order things by most irresponsible country to least
dplyr::count(dat, country) %>%
     arrange(desc(n)) %>%
     mutate(country=factor(country, levels=unique(country))) -> booms

# Intercourse Antarctica
world_map <- filter(map_data("world"), region!="Antarctica")

scary <- "#2B2C27" # a.k.a "slate black"
light <- "#bfbfbf" # a.k.a "off white"

proj <- "+proj=kav7" # Winkel-Tripel is *so* 2015

# In the original code I was using to play around with various themeing
# and display options this encapsulated theme_ function really helped alot
# but to do the grid.arrange with the bars it only ended up saving a teensy
# bit of typing.
#
# Also, Tungsten is ridiculously expensive but I have access via corporate
# subscriptions, so I'd suggest going with Arial Narrow vs draining your
# bank account since I really like the detailed kerning pairs but also think
# that it's just a tad too narrow. It seemed fitting for this vis, tho.

theme_scary_world_map <- function(scary="#2B2C27", light="white") {
     theme_map() +
          theme(text=element_text(family="Roboto Condensed"),
                title=element_text(family="Roboto Condensed"),
                plot.background=element_rect(fill=scary, color=scary),
                panel.background=element_rect(fill=scary, color=scary),
                legend.background=element_rect(fill=scary),
                legend.key=element_rect(fill=scary, color=scary),
                legend.text=element_text(color=light, size=10),
                legend.title=element_text(color=light),
                axis.title=element_text(color=light),
                axis.title.x=element_text(color=light, family="Roboto Condensed", size=14),
                axis.title.y=element_blank(),
                plot.title=element_text(color=light, face="bold", size=16),
                plot.subtitle=element_text(color=light, family="Roboto Condensed",
                                           size=13, margin=margin(b=14)),
                plot.caption=element_text(color=light, family="Roboto Condensed",
                                          size=9, margin=margin(t=10)),
                plot.margin=margin(0, 0, 0, 0),
                legend.position="bottom")
}

# I wanted to see booms by unique coords
dplyr::count(dat, year, country, latitude, longitude) %>%
     ungroup() %>%
     mutate(country=factor(country, levels=unique(booms$country))) -> dat_agg

years <- as.character(seq(1945, 1998, 1))

# place to hold the pngs
dir.create("booms", FALSE)

# I ended up lovingly hand-crafting ffmpeg parameters to get the animation to
# work with Twitter's posting guidelines. A plain 'old ImageMagick "convert"
# from multiple png's to animated gif will work fine for a local viewing

til <- length(years)
pb <- progress_estimated(til)
suppressWarnings(walk(1:til, function(i) {
     
     pb$tick()$print()
     
     # data for map
     tmp_dat <- filter(dat_agg, year<=years[i])
     
     # data for bars
     dplyr::count(tmp_dat, country, wt=n) %>%
          arrange(desc(nn)) %>%
          mutate(country=factor(country, levels=unique(country))) %>%
          complete(country, fill=list(nn=0)) -> boom2 # this gets us all the countries on the barplot x-axis even if the had no booms yet
     
     gg <- ggplot()
     gg <- gg + geom_map(data=world_map, map=world_map,
                         aes(x=long, y=lat, map_id=region),
                         color=light, size=0.1, fill=scary)
     gg <- gg + geom_point(data=tmp_dat,
                           aes(x=longitude, y=latitude, size=n, color=country),
                           shape=21, stroke=0.3)
     
     # the "trick" here is to force the # of labeled breaks so ggplot2 doesn't
     # truncate the range on us (it's nice that way and that feature is usually helpful)
     gg <- gg + scale_radius(name="", range=c(2, 8), limits=c(1, 50),
                             breaks=c(5, 10, 25, 50),
                             labels=c("1-4", "5-9", "10-24", "25-50"))
     
     gg <- gg + scale_color_brewer(name="", palette="Set1", drop=FALSE)
     gg <- gg + coord_proj(proj)
     gg <- gg + labs(x=years[i], y=NULL, title="Nuclear Explosions, 1945–1998",
                     subtitle="Stockholm International Peace Research Institute (SIPRI) and Sweden's Defence Research Establishment",
                     caption=NULL)
     
     # order doesn't actually work but it will after I get a PR into ggplot2
     # the tweaks here let us make the legends look like we want vs just mapped
     # to the aesthetics
     gg <- gg + guides(size=guide_legend(override.aes=list(color=light, stroke=0.5)),
                       color=guide_legend(override.aes=list(alpha=1, shape=16, size=3), nrow=1))
     
     gg <- gg + theme_scary_world_map(scary, light)
     gg <- gg + theme(plot.margin=margin(t=6, b=-1.5, l=4, r=4))
     gg_map <- gg
     
     gg
     
     gg <- ggplot(boom2, aes(x=country, y=nn))
     gg <- gg + geom_bar(stat="identity", aes(fill=country), width=0.5, color=light, size=0.05)
     gg <- gg + scale_x_discrete(expand=c(0,0))
     gg <- gg + scale_y_continuous(expand=c(0,0), limits=c(0, 1100))
     gg <- gg + scale_fill_brewer(name="", palette="Set1", drop=FALSE)
     gg <- gg + labs(x=NULL, y=NULL, title=NULL, subtitle=NULL,
                     caption="Data from https://github.com/data-is-plural/nuclear-explosions")
     gg <- gg + theme_scary_world_map(scary, light)
     gg <- gg + theme(axis.text=element_text(color=light))
     gg <- gg + theme(axis.text.x=element_text(color=light, size=11, margin=margin(t=2)))
     gg <- gg + theme(axis.text.y=element_text(color=light, size=6, margin=margin(r=5)))
     gg <- gg + theme(axis.title.x=element_blank())
     gg <- gg + theme(plot.margin=margin(l=20, r=20, t=-1.5, b=5))
     gg <- gg + theme(panel.grid=element_line(color=light, size=0.15))
     gg <- gg + theme(panel.margin=margin(0, 0, 0, 0))
     gg <- gg + theme(panel.grid.major.x=element_blank())
     gg <- gg + theme(panel.grid.major.y=element_line(color=light, size=0.05))
     gg <- gg + theme(panel.grid.minor=element_blank())
     gg <- gg + theme(panel.grid.minor.x=element_blank())
     gg <- gg + theme(panel.grid.minor.y=element_blank())
     gg <- gg + theme(axis.line=element_line(color=light, size=0.1))
     gg <- gg + theme(axis.line.x=element_line(color=light, size=0.1))
     gg <- gg + theme(axis.line.y=element_blank())
     gg <- gg + theme(legend.position="none")
     gg_bars <- gg
     
     # dimensions arrived at via trial and error
     
     png(sprintf("./booms/frame_%03d.png", i), width=980*2.5, height=500*2, res=144, bg=scary)
     grid.arrange(gg_map, gg_bars, ncol=1, heights=c(0.85, 0.15), padding=unit(0, "null"), clip="on")
     dev.off()
     
}))



system("convert  -antialias -delay 20 -quality 97 booms/*.png Figures/nuclear.mp4", wait = TRUE)
