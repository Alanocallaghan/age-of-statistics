devtools::load_all()
library(dplyr)
library(ggplot2)
library(scales)
library(lubridate)
library(arrow)

data_location <- get_data_location()



matchmeta <- read_parquet(
    file.path(data_location, "matchmeta.parquet")
)


#######################################
#
# Hist plot of ELo counts
#
#######################################


elo <- matchmeta$rating_mean

lb <- floor(min(elo) / 100) * 100
ub <- ceiling(max(elo) / 100) * 100
cuts <- seq(lb, ub, by = 100)


pdat <- matchmeta %>%
    mutate(elocat = cut(rating_mean, cuts, right = FALSE, dig.lab = 4)) %>%
    group_by(elocat) %>%
    tally() %>%
    mutate(p = sprintf("%4.1f%%", n / sum(n) * 100)) %>%
    mutate(yadj = n + max(n) / 50)


strings <- matchmeta %>%
    mutate(elo = rating_mean) %>%
    summarise(
        n = length(elo),
        min = min(elo),
        lower.q = quantile(elo, 0.25),
        median = quantile(elo, 0.5),
        mean = mean(elo),
        upper.q = quantile(elo, 0.75),
        max = max(elo)
    ) %>%
    pivot_longer(everything()) %>%
    mutate(string = sprintf( "%s = %7.0f", name, value) %>% str_pad(width = 12)) %>%
    pull(string) %>%
    paste0(collapse = "\n")


footnotes <- c(
    "The mean match Elo is calculated as the mean Elo of all players in the match"
) %>%
    as_footnote()


p <- ggplot(pdat, aes(x = elocat, y = n)) +
    geom_bar(stat = "identity") +
    geom_text(aes(label = p, y = yadj)) + 
    theme_bw() +
    ylab("Count") +
    scale_y_continuous(breaks = pretty_breaks(10), expand = expansion(c(0, 0.06))) +
    scale_x_discrete(expand = expansion(c(0, 0.06))) +
    xlab("Mean Match Elo") +
    annotate(
        geom = "text",
        label = strings,
        x = nrow(pdat),
        y = Inf,
        hjust = 1,
        vjust = 1.1
    ) +
    theme(
        plot.caption = element_text(hjust = 0),
        axis.text.x = element_text(hjust = 1, angle = 35)
    ) +
    labs(caption = footnotes)


save_plot(
    p = p,
    id = "dist_elo",
    type = "standard"
)




#######################################
#
# Hist plot of Patch version
#
#######################################

pdat <- matchmeta %>%
    group_by(version) %>%
    tally() %>%
    mutate(p = sprintf("%4.1f%%", n / sum(n) * 100)) %>%
    mutate(yadj = n + max(n) / 50)

p <- ggplot(data = pdat, aes(x = version, y = n)) +
    geom_bar(stat = "identity") +
    geom_text(aes(label = p, y = yadj)) +
    theme_bw() +
    scale_y_continuous(breaks = pretty_breaks(8), expand = expansion(c(0, 0.05))) +
    xlab("Patch Version") +
    ylab("Number of Games") +
    theme(plot.caption = element_text(hjust = 0)) +
    labs(caption = as_footnote(""))


save_plot(
    p = p,
    id = "dist_patch",
    type = "standard"
)





#######################################
#
# Map distribtuons
#
#######################################


pdat <- matchmeta %>%
    mutate(bign = n()) %>%
    group_by(map) %>%
    summarise(
        n = n(),
        p = sprintf("%5.2f%%", n / unique(bign) * 100),
        bign = unique(bign),
        .group = "drop"
    ) %>% 
    mutate(yjust = n + max(n)/50)


p <- ggplot(data = pdat, aes(x = map, y = n)) +
    geom_bar(stat = "identity") +
    geom_text(aes(label = p, y = yjust)) +
    theme_bw() +
    scale_y_continuous(breaks = pretty_breaks(8), expand = expansion(c(0, 0.05))) +
    xlab("Map") +
    ylab("Number of Games") +
    theme(
        plot.caption = element_text(hjust = 0),
        axis.text.x = element_text(hjust = 1, angle = 35)
    ) +
    theme(plot.caption = element_text(hjust = 0)) +
    labs(caption = as_footnote(""))


save_plot(
    p = p,
    id = "dist_map",
    type = "standard"
)








#######################################
#
# Map distribtuons normalised
#
#######################################


matchmeta_with_day <- matchmeta %>%
    mutate(match_day_num = as.numeric(as.Date(start_dt)))

numerator <- matchmeta_with_day %>%
    distinct(match_day_num, map) %>%
    group_by(map) %>%
    tally(name = "num")

denominator <- matchmeta_with_day %>%
    distinct(match_day_num) %>%
    nrow()

pdat <- matchmeta %>%
    group_by(map) %>%
    tally() %>%
    left_join(numerator, by = "map") %>%
    mutate(scale = num / denominator) %>%
    mutate(n_normal = n / scale) %>%
    mutate(bign = sum(n_normal)) %>%
    group_by(map) %>%
    summarise(
        n = n_normal,
        p = sprintf("%5.2f%%", n / unique(bign) * 100),
        bign = unique(bign)
    ) %>%
    mutate(yjust = n + max(n) / 50)

footnotes <- as_footnote(
    c(
        "Play rates have been normalised by scaling the number of games played by 1 divided by",
        "the percentage<br/>of days in which at least 1 game was played on that map"
    )
)

p <- ggplot(data = pdat, aes(x = map, y = n)) +
    geom_bar(stat = "identity") +
    geom_text(aes(label = p, y = yjust)) +
    theme_bw() +
    scale_y_continuous(breaks = pretty_breaks(8), expand = expansion(c(0, 0.05))) +
    xlab("Map") +
    ylab("Number of Games") +
    theme(
        plot.caption = element_text(hjust = 0),
        axis.text.x = element_text(hjust = 1, angle = 35)
    ) +
    theme(plot.caption = element_text(hjust = 0)) +
    labs(caption = footnotes)


save_plot(
    p = p,
    id = "dist_map_normal",
    type = "standard"
)






#######################################
#
# Game Length
#
#######################################



glen <- matchmeta$match_length_igm
ub <- ceiling(quantile(glen, 0.95) / 5) * 5

cuts <- c(seq(0, ub, by = 5), Inf)


pdat <- matchmeta %>%
    mutate(lencat = cut(match_length_igm, cuts, right = FALSE, dig.lab = 4)) %>%
    group_by(lencat) %>%
    tally() %>%
    mutate(p = sprintf("%4.1f%%", n / sum(n) * 100)) %>%
    mutate(yadj = n + max(n) / 50)


strings <- matchmeta %>%
    summarise(
        n = length(match_length_igm),
        min = min(match_length_igm),
        lower.q = quantile(match_length_igm, 0.25),
        median = quantile(match_length_igm, 0.5),
        mean = mean(match_length_igm),
        upper.q = quantile(match_length_igm, 0.75),
        max = max(match_length_igm)
    ) %>%
    pivot_longer(everything()) %>%
    mutate(string = sprintf("%s = %7.0f", name, value) %>% str_pad(width = 12)) %>%
    pull(string) %>%
    paste0(collapse = "\n")


p <- ggplot(pdat, aes(x = lencat, y = n)) +
    geom_bar(stat = "identity") +
    geom_text(aes(label = p, y = yadj)) +
    theme_bw() +
    ylab("Count") +
    scale_y_continuous(breaks = pretty_breaks(10), expand = expansion(c(0, 0.06))) +
    scale_x_discrete(expand = expansion(c(0, 0.06))) +
    xlab("Game Length (in-game minutes)") +
    annotate(
        geom = "text",
        label = strings,
        x = nrow(pdat),
        y = Inf,
        hjust = 1,
        vjust = 1.1
    ) +
    theme(axis.text.x = element_text(hjust = 1, angle = 35)) +
    theme(plot.caption = element_text(hjust = 0)) +
    labs(caption = as_footnote(""))


save_plot(
    p = p,
    id = "dist_gamelength",
    type = "standard"
)



set_log(get_output_location(), "descriptives")

