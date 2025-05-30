#' @importFrom stats runif rbinom
#' @importFrom methods new
generate.eqspace.zigzags <- function(design, strata.id, samplers, line.length, spacing, by.spacing, calc.cov.area = TRUE, clip.to.strata = TRUE, quiet = FALSE){
  #Generates equal spaced zigzags, optionally with a complementary set of zigzags
  region <- design@region
  sf.column <- attr(region@region, "sf_column")
  #Get the current strata and spacing
  strata <- region@region[[sf.column]][[strata.id]]
  #Spin round so design angle lies along x axis
  rot.angle.rad <- design@design.angle[strata.id]+90
  rot.angle.rad <- rot.angle.rad/180*pi
  theta <- ifelse(rot.angle.rad == 0, 0, 2*pi-rot.angle.rad)
  rot.mat <- matrix(c(cos(theta), sin(theta), -sin(theta), cos(theta)), ncol = 2, byrow = FALSE)
  rot.strata <- mat.mult(strata, rot.mat)
  #Buffer strata for plus sampling?
  if(design@edge.protocol[strata.id] == "plus"){
    rot.strata <- sf::st_buffer(rot.strata, design@truncation)
  }
  #Find the minimum and maximum x and y values
  bbox <- sf::st_bbox(rot.strata)
  if(!by.spacing && is.na(samplers)){
    #Calculate from line.length
    width <- bbox$xmax - bbox$xmin
    names(width) <- NULL
    ave.line.height <- sf::st_area(rot.strata)/width
    if(design@design[strata.id] == "eszigzag"){
      if(line.length < width){
        if(!quiet){
          warning("Line length in strata ", strata.id, " is not sufficient to carry out an equal spaced zigzag design. No samplers generated for this strata.", immediate. = TRUE, call. = FALSE)
        }
        return(NULL)
      }
      spacing = (width * ave.line.height) / sqrt(line.length^2 - width^2)
    }else{
      if(line.length/2 < width){
        if(!quiet){
          warning("Line length in strata ", strata.id, " is not sufficient to carry out a complementary equal spaced zigzag design. No samplers generated for this strata.", immediate. = TRUE, call. = FALSE)
        }
        return(NULL)
      }
      spacing = (width * ave.line.height) / sqrt((line.length/2)^2 - width^2)
    }
    by.spacing = TRUE
  }
  if(!by.spacing){
    spacing <- (bbox[["xmax"]]-bbox[["xmin"]])/(samplers)
    if(design@design[strata.id] == "eszigzagcom"){
      spacing <- spacing * 2
    }
  }
  if(spacing > (bbox[["xmax"]]-bbox[["xmin"]])){
    if(!quiet){
      warning(paste("Spacing larger than x-range cannot generate samplers in strata ", strata.id, sep = ""), immediate. = T, call. = F)
    }
    return(NULL)
  }
  start.x <- bbox[["xmin"]] #+ runif(1, 0, spacing) - spacing
  x.vals <- seq(start.x, (bbox[["xmax"]] + spacing), by = spacing)
  start.y <- rep(bbox[["ymin"]], length(x.vals))
  end.y <- rep(bbox[["ymax"]], length(x.vals))
  if(design@bounding.shape[strata.id] == "convex.hull"){
    clipped.vals <- get.intersection.points(rot.strata, x.vals, start.y, end.y)
    start.y <- clipped.vals$start.y
    end.y <- clipped.vals$end.y
  }
  #Randomise zig or zag at start
  random.start <- start.x
  #Create the lines
  lines <- list()
  #counter <- 1
  zz.set <- "A"
  if(design@design[strata.id] == "eszigzagcom"){
    for(i in 1:(length(x.vals)-1)){
      #Do zig
      lines[[paste("set", zz.set, ".tr", i, sep = "")]] <- sf::st_linestring(matrix(c(x.vals[i], x.vals[i+1], start.y[i], end.y[i+1]), ncol = 2))
      #counter <- counter + 1
      zz.set <- ifelse(zz.set == "A", "B", "A")
      #and complementing zag
      lines[[paste("set", zz.set, ".tr", i, sep = "")]] <- sf::st_linestring(matrix(c(x.vals[i], x.vals[i+1], end.y[i], start.y[i+1]), ncol = 2))
      #counter <- counter + 1
    }
  }else{
    zig <- ifelse(random.start == 1, TRUE, FALSE)
    for(i in 1:(length(x.vals)-1)){
      #Do zig
      if(zig){
        lines[[i]] <- sf::st_linestring(matrix(c(x.vals[i], x.vals[i+1], start.y[i], end.y[i+1]), ncol = 2))
      }else{
        #zag
        lines[[i]] <- sf::st_linestring(matrix(c(x.vals[i], x.vals[i+1], end.y[i], start.y[i+1]), ncol = 2))
      }
      #reverse for next time
      zig <- ifelse(zig, FALSE, TRUE)
    }
  }
  #keep everything within the polygon strata
  to.keep <- lapply(lines, sf::st_intersection, y = rot.strata)
  #Only keep lines (discard points - fragments of line so small they have become points)
  test.line <- function(x){ifelse(inherits(x, "LINESTRING") || inherits(x, "MULTILINESTRING"), TRUE, FALSE)}
  is.line <- which(unlist(lapply(to.keep, FUN = test.line)))
  to.keep <- to.keep[is.line]
  #Calculate covered region - do it here as easier before unrotating!
  cover.polys <- list()
  if(calc.cov.area){
    trunctn <- design@truncation
    xend1 <- xend2 <- numeric(0)
    for(tr in seq(along = to.keep)){
      if(inherits(to.keep[[tr]], "LINESTRING")){
        #Find end points
        lx <- to.keep[[tr]][,1]
        ly <- to.keep[[tr]][,2]
        #Find gradients
        lm <- (ly[2]-ly[1])/(lx[2]-lx[1])
        if(lm == 0){
          x.vals <- lx[c(1,1,2,2,1)]
          y.vals <- c(ly[1]-trunctn, rep(ly[1]+trunctn,2), rep(ly[1]-trunctn, 2))
        }else if(lm == Inf){
          x.vals <- c(rep(lx[1]-trunctn,2), rep(lx[1]+trunctn,2), lx[1]-trunctn)
          y.vals <- ly[c(1,2,2,1,1)]
        }else{
          pm <- -1*(1/lm)
          #Calculate x coordinates
          xend1[1] <- lx[1] - trunctn/sqrt(1+pm^2)
          xend1[2] <- lx[1] + trunctn/sqrt(1+pm^2)
          xend2[1] <- lx[2] - trunctn/sqrt(1+pm^2)
          xend2[2] <- lx[2] + trunctn/sqrt(1+pm^2)
          x.vals <- c(xend1[1], xend2, xend1[2:1])
          x0 <- c(lx[1], lx[2], lx[2], lx[1], lx[1])
          y0 <- c(ly[1], ly[2], ly[2], ly[1], ly[1])
          y.vals = pm*(x.vals-x0)+y0
        }
        cover.polys[[tr]] <- sf::st_polygon(list(matrix(c(x.vals, y.vals), ncol = 2)))
      }else if(inherits(to.keep[[tr]], "MULTILINESTRING")){
        #Need to iterate along the list
        temp <- list()
        for(part in seq(along = to.keep[[tr]])){
          #Find end points
          lx <- to.keep[[tr]][[part]][,1]
          ly <- to.keep[[tr]][[part]][,2]
          #Find gradients
          lm <- (ly[2]-ly[1])/(lx[2]-lx[1])
          if(lm == 0){
            x.vals <- lx[c(1,1,2,2,1)]
            y.vals <- c(ly[1]-trunctn, rep(ly[1]+trunctn,2), rep(ly[1]-trunctn, 2))
          }else if(lm == Inf){
            x.vals <- c(rep(lx[1]-trunctn,2), rep(lx[1]+trunctn,2), lx[1]-trunctn)
            y.vals <- ly[c(1,2,2,1,1)]
          }else{
            pm <- -1*(1/lm)
            #Calculate x coordinates
            xend1[1] <- lx[1] - trunctn/sqrt(1+pm^2)
            xend1[2] <- lx[1] + trunctn/sqrt(1+pm^2)
            xend2[1] <- lx[2] - trunctn/sqrt(1+pm^2)
            xend2[2] <- lx[2] + trunctn/sqrt(1+pm^2)
            x.vals <- c(xend1[1], xend2, xend1[2:1])
            x0 <- c(lx[1], lx[2], lx[2], lx[1], lx[1])
            y0 <- c(ly[1], ly[2], ly[2], ly[1], ly[1])
            y.vals = pm*(x.vals-x0)+y0
          }
          temp[[part]] <- list(matrix(c(x.vals, y.vals), ncol = 2))
        }
        cover.polys[[tr]] <- sf::st_multipolygon(temp)
      }
    }
  }
  #Check if any polygons are invalid - sometimes tiny pieces of line are generated on the boundaries which lead to overlapping multi polygons
  invalid <- which(!unlist(lapply(cover.polys, sf::st_is_valid)))
  for(i in seq(along = invalid)){
    tmp <- cover.polys[[invalid[i]]]
    polys.tmp <- list()
    mat.tmp <- list()
    for(poly in seq(along = tmp)){
      polys.tmp[[poly]] <- sf::st_polygon(tmp[[poly]])
      mat.tmp[[poly]] <- tmp[[poly]]
    }
    to.rem <- numeric(0)
    for(poly in seq(along = polys.tmp)){
      intsec <- which(unlist(lapply(polys.tmp, sf::st_intersects, polys.tmp[poly][[1]], sparse = FALSE)))[-poly]
      if(length(intsec) > 0){
        intsec <- sort(c(intsec, poly))
        areas <- unlist(lapply(polys.tmp[intsec], sf::st_area))
        to.rem <- c(to.rem, intsec[which(areas == min(areas))])
        #if(min(areas) > sf::st_area(rot.strata)/50000){
        #  warning("Removing covered area greater than 50,000th of the strata area.", immediate. = TRUE, call. = FALSE)
        #}
      }
    }
    to.rem <- unique(to.rem)
    new.polys <- mat.tmp[-to.rem]
    if(length(new.polys) == 1){
      cover.polys[[invalid[i]]] <- sf::st_polygon(new.polys[[1]])
    }else{
      cover.polys[[invalid[i]]] <- sf::st_multipolygon(new.polys)
    }
    #Also remove strange corresponding transect part
    tmp <- to.keep[[invalid[i]]]
    if(length(tmp[-to.rem]) == 1){
      to.keep[[invalid[i]]] <- sf::st_linestring(tmp[-to.rem][[1]])
    }else{
      to.keep[[invalid[i]]] <- sf::st_multilinestring(tmp[-to.rem])
    }
  }
  #Clip to strata
  if(clip.to.strata){
   cover.polys <- lapply(cover.polys, sf::st_intersection, y = rot.strata)
  }
  #Rotate back again
  reverse.theta <- rot.angle.rad
  rot.mat.rev <- matrix(c(cos(reverse.theta), sin(reverse.theta), -sin(reverse.theta), cos(reverse.theta)), ncol = 2, byrow = FALSE)
  lines.unrotated <- lapply(to.keep, mat.mult, y=rot.mat.rev)
  transects <- lines.unrotated
  #Also rotate covered region
  if(calc.cov.area){
    cover.polys.unrot <- lapply(cover.polys, mat.mult, y = rot.mat.rev)
    return(list(transects = transects, cover.polys = cover.polys.unrot, spacing = spacing))
  }
  return(list(transects = transects, cover.polys = list(), spacing = spacing))
}
