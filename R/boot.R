###############################################
## Inference 
###############################################
fect.boot <- function(Y,
                      X,
                      D,
                      cl = NULL,
                      I,
                      II, 
                      T.on, 
                      T.off = NULL, 
                      method = "ife",
                      degree = 2,
                      knots = NULL,
                      criterion = "mspe",
                      CV,
                      k = 5,
                      r = 0, 
                      r.end,
                      lambda = NULL,
                      nlambda = 10,
                      alpha = 0.05,
                      binary,
                      QR,
                      force,                      
                      hasRevs = 1,
                      tol,
                      norm.para,
                      placebo.period = NULL,
                      placeboTest = FALSE,
                      vartype = "bootstrap",
                      nboots,
                      parallel = TRUE,
                      cores = NULL,
                      group = NULL) {
    
    
    na.pos <- NULL
    TT <- dim(Y)[1]
    N <- dim(Y)[2]
    if (is.null(X) == FALSE) {
        p <- dim(X)[3]
    } else {
        p <- 0
    }

    if (hasRevs == 1) {
        ## D.fake : check reversals
        D.fake <- apply(D, 2, function(vec){cumsum(vec)})
        D.fake <- ifelse(D.fake > 0, 1, 0)
        D.fake[which(I == 0)] <- 0

        rev <- which(apply(D.fake == D, 2, sum) != TT)
        co <- which(apply(D, 2, sum) == 0)
        tr.all <- which(apply(D, 2, sum) > 0)
        tr <- tr.all[which(!tr.all %in% rev)]

        Nrev <- length(rev)
        Ntr <- length(tr)
        Nco <- length(co)
    } else {
        ## treatement indicator
        tr <- which(apply(D, 2, sum) > 0)
        co <- which(apply(D, 2, sum) == 0)

        Ntr <- length(tr)
        Nco <- length(co)
    }

    
    ## estimation
    if (CV == 0) { 
        if (method == "ife") {
            out <- fect.fe(Y = Y, X = X, D = D, I = I, II = II, 
                           T.on = T.on, T.off = T.off,
                           r.cv = r, binary = binary, QR = QR,
                           force = force, hasRevs = hasRevs, 
                           tol = tol, boot = 0,
                           norm.para = norm.para, 
                           placebo.period = placebo.period,
                           placeboTest = placeboTest,
                           group = group)
        
        } else if (method == "mc") {
            out <- fect.mc(Y = Y, X = X, D = D, I = I, II = II,
                           T.on = T.on, T.off = T.off, 
                           lambda.cv = lambda, force = force, hasRevs = hasRevs, 
                           tol = tol, boot = 0,
                           norm.para = norm.para,
                           placebo.period = placebo.period,
                           placeboTest = placeboTest,
                           group = group)
        
        } else if (method %in% c("polynomial", "bspline")) {
            out <- try(fect.polynomial(Y = Y, D = D, X = X, I = I, 
                                   II = II, T.on = T.on, 
                                   T.off = T.off,
                                   method = method,degree = degree,
                                   knots = knots, force = force, 
                                   hasRevs = hasRevs,
                                   tol = tol, boot = 0, 
                                   placeboTest = placeboTest,
                                   placebo.period = placebo.period, 
                                   norm.para = norm.para,
                                   group = group), silent = TRUE)

            if ('try-error' %in% class(out)) {
                stop("\nCannot estimate.\n")
            }
        }
    } else {
        ## cross-valiadtion 
        if (binary == 0) {
            out <- fect.cv(Y = Y, X = X, D = D, I = I, II = II, 
                       T.on = T.on, T.off = T.off,
                       method = method, criterion = criterion,
                       k = k, r = r, r.end = r.end, 
                       nlambda = nlambda, lambda = lambda, 
                       force = force, hasRevs = hasRevs, 
                       tol = tol, norm.para = norm.para,
                       group = group)

            method <- out$method
        } else {
            out <- fect.binary.cv(Y = Y, X = X, D = D, 
                                  I = I, II = II, 
                                  T.on = T.on, T.off = T.off,
                                  k = k, r = r, r.end = r.end, 
                                  QR = QR, force = force, 
                                  hasRevs = hasRevs, tol = tol)
            method <- "ife"
        }
        
    }
    
    
    ## output
    validX <- out$validX
    eff <- out$eff
    att.avg <- out$att.avg
    att.avg.unit <- out$att.avg.unit

    group.att <- out$group.att

    att.on <- out$att
    time.on <- out$time

    time.off <- NULL
    if (hasRevs == 1) {
        att.off <- out$att.off
        time.off <- out$time.off
    }

    if (p > 0) {
        beta <- out$beta
    } else {
        beta <-matrix(0,1,0)
    }

    if (is.null(cl)) {
        cl.unique <- NULL
    } else {
        cl.unique <- unique(cl)
    }

    if (vartype == "jackknife") {
        nboots <- N
    }
 
    ## bootstrapped estimates
    ## eff.boot <- array(0,dim = c(TT, Ntr, nboots))  ## to store results
    att.avg.boot <- matrix(0, 1, nboots)
    att.avg.unit.boot <- matrix(0, 1, nboots)
    att.on.boot <- matrix(0, length(time.on), nboots)
    att.on.count.boot <- matrix(0, length(time.on), nboots)
    if (hasRevs == 1) {
        att.off.boot <- matrix(0, length(time.off), nboots) 
        att.off.count.boot <- matrix(0, length(time.off), nboots)   
    }
    if (p > 0) {
        beta.boot <- matrix(0, p, nboots)
    }
    if (!is.null(placebo.period) & placeboTest == TRUE) {
        att.placebo.boot <- matrix(0, 1, nboots)
    }

    group.att.boot <- NULL
    if (!is.null(group.att)) {
        group.att.boot <- matrix(0, length(group.att), nboots)
    } 

    if (vartype == "jackknife") {
        cat("Jackknife estimates ... ")
    } else {
        cat("Bootstrapping for uncertainties ... ")
    }
    
 
    #if (method == "ife") {
        one.nonpara <- function(num = NULL) {

            if (is.null(num)) {
                if (is.null(cl)) {
                    if (hasRevs == 0) {
                        if (Nco > 0) {
                            repeat{
                                fake.co <- sample(co, Nco, replace=TRUE)
                                fake.tr <- sample(tr, Ntr, replace=TRUE)
                                boot.id <- c(fake.tr, fake.co)
                                if (sum(apply(as.matrix(I[,boot.id]),1,sum)>=1)==TT) {
                                    break
                                }
                            }
                        } else {
                            repeat{
                                boot.id <- sample(tr, Ntr, replace=TRUE)
                                if (sum(apply(as.matrix(I[,boot.id]),1,sum)>=1)==TT) {
                                    break
                                }
                            }
                        }
                    } else {
                        if (Ntr > 0) {
                            if (Nco > 0) {
                                repeat{
                                    fake.co <- sample(co, Nco, replace=TRUE)
                                    fake.tr <- sample(tr, Ntr, replace=TRUE)
                                    fake.rev <- sample(rev, Nrev, replace=TRUE)
                                    boot.id <- c(fake.rev, fake.tr, fake.co)
                                    if (sum(apply(as.matrix(I[,boot.id]),1,sum)>=1)==TT) {
                                        break
                                    }
                                }
                            } else {
                                repeat{
                                    fake.tr <- sample(tr, Ntr, replace=TRUE)
                                    fake.rev <- sample(rev, Nrev, replace=TRUE)
                                    boot.id <- c(fake.rev, fake.tr)
                                    if (sum(apply(as.matrix(I[,boot.id]),1,sum)>=1)==TT) {
                                        break
                                    }
                                }
                            }
                        } else {
                            if (Nco > 0) {
                                repeat{
                                    fake.co <- sample(co, Nco, replace=TRUE)
                                    fake.rev <- sample(rev, Nrev, replace=TRUE)
                                    boot.id <- c(fake.rev, fake.co)
                                    if (sum(apply(as.matrix(I[,boot.id]),1,sum)>=1)==TT) {
                                        break
                                    }
                                }
                            } else {
                                repeat{
                                    boot.id <- sample(rev, Nrev, replace=TRUE)
                                    if (sum(apply(as.matrix(I[,boot.id]),1,sum)>=1)==TT) {
                                        break
                                    }
                                }
                            }
                        }
                    }
                } else {
                    cl.boot <- sample(cl.unique, length(cl.unique), replace = TRUE)
                    cl.boot.uni <- unique(cl.boot)
                    cl.boot.count <- as.numeric(table(cl.boot))
                    boot.id <- c()
                    for (kk in 1:length(cl.boot.uni)) {
                        boot.id <- c(boot.id, rep(which(cl == cl.boot.uni[kk]), cl.boot.count[kk]))
                    }
                }

                boot.group <- NULL

            } else { ## jackknife
                boot.group <- group[,-num]
                boot.id <- 1:N
                boot.id <- boot.id[-num]
            }
            
            X.boot <- X[,boot.id,,drop = FALSE]
            D.boot <- D[, boot.id]
            I.boot <- I[, boot.id]

            if (sum(c(D.boot) == 0) == 0 | sum(c(D.boot) == 1) == 0 | sum(c(I.boot) == 1) == 0) {
                boot0 <- list(att.avg = NA, att = NA, count = NA, 
                              beta = NA, att.off = NA, count.off = NA, 
                              att.placebo = NA, att.avg.unit = NA)
                return(boot0)
            } else {
                T.off.boot <- NULL
                if (hasRevs == TRUE) {
                    T.off.boot <- T.off[, boot.id]
                }
                placebo.period.boot <- NULL
                if (placeboTest == TRUE) {
                    placebo.period.boot <- placebo.period
                }


                if (method == "ife") {
                    boot <- try(fect.fe(Y = Y[, boot.id], X = X.boot, D = D.boot,
                                    I = I.boot, II = II[, boot.id], 
                                    T.on = T.on[, boot.id], T.off = T.off.boot, 
                                    r.cv = out$r.cv, binary = binary,
                                    QR = QR, force = force,
                                    hasRevs = hasRevs, tol = tol, boot = 1,
                                    norm.para = norm.para,
                                    time.on.seq = time.on, time.off.seq = time.off,
                                    placebo.period = placebo.period.boot, 
                                    placeboTest = placeboTest,
                                    group = boot.group), silent = TRUE)
                } else if (method == "mc") {
                    boot <- try(fect.mc(Y = Y[,boot.id], X = X.boot, D = D[,boot.id],
                                    I = I[,boot.id], II = II[,boot.id],
                                    T.on = T.on[,boot.id], T.off = T.off.boot, 
                                    lambda.cv = out$lambda.cv, force = force, 
                                    hasF = out$validF, hasRevs = hasRevs, 
                                    tol = tol, boot = 1,
                                    norm.para = norm.para,
                                    time.on.seq = time.on, time.off.seq = time.off,
                                    placebo.period = placebo.period.boot, 
                                    placeboTest = placeboTest,
                                    group = boot.group), silent = TRUE)

                } else if (method %in% c("polynomial", "bspline")) {
                    boot <- try(fect.polynomial(Y = Y[,boot.id], X = X.boot, 
                                                D = D[,boot.id],
                                                I = I[,boot.id], II = II[,boot.id],
                                                T.on = T.on[,boot.id], T.off = T.off.boot, 
                                                method = method,degree = degree, knots = knots,
                                                force = force, hasRevs = hasRevs,
                                                norm.para = norm.para, time.on.seq = time.on, 
                                                time.off.seq = time.off,
                                                placebo.period = placebo.period.boot, 
                                                placeboTest = placeboTest,
                                                group = boot.group), silent = TRUE)
                }

                if ('try-error' %in% class(boot)) {
                    boot0 <- list(att.avg = NA, att = NA, count = NA, 
                                  beta = NA, att.off = NA, count.off = NA, 
                                  att.placebo = NA, att.avg.unit = NA)
                    return(boot0)
                } else {
                    return(boot)
                }
            }            
        } 
            
    #} else { ## mc
    #    one.nonpara <- function() {

    #        if (is.null(num)) {
    #            if (is.null(cl)) {
    #                if (hasRevs == 0) {
    #                    if (Nco > 0) {
    #                        repeat{
    #                            fake.co <- sample(co, Nco, replace=TRUE)
    #                            fake.tr <- sample(tr, Ntr, replace=TRUE)
    #                            boot.id <- c(fake.tr, fake.co)
    #                            if (sum(apply(as.matrix(I[,boot.id]),1,sum)>=1)==TT) {
    #                                break
    #                            }
    #                        }
    #                    } else {
    #                        repeat{
    #                            boot.id <- sample(tr, Ntr, replace=TRUE)
    #                            if (sum(apply(as.matrix(I[,boot.id]),1,sum)>=1)==TT) {
    #                                break
    #                            }
    #                        }
    #                    }
    #                } else {
    #                    if (Ntr > 0) {
    #                        if (Nco > 0) {
    #                            repeat{
    #                                fake.co <- sample(co, Nco, replace=TRUE)
    #                                fake.tr <- sample(tr, Ntr, replace=TRUE)
    #                                fake.rev <- sample(rev, Nrev, replace=TRUE)
    #                                boot.id <- c(fake.rev, fake.tr, fake.co)
    #                                if (sum(apply(as.matrix(I[,boot.id]),1,sum)>=1)==TT) {
    #                                    break
    #                                }
    #                            }
    #                        } else {
    #                            repeat{
    #                                fake.tr <- sample(tr, Ntr, replace=TRUE)
    #                                fake.rev <- sample(rev, Nrev, replace=TRUE)
    #                                boot.id <- c(fake.rev, fake.tr)
    #                                if (sum(apply(as.matrix(I[,boot.id]),1,sum)>=1)==TT) {
    #                                    break
    #                                }
    #                            }
    #                        }
    #                    } else {
    #                        if (Nco > 0) {
    #                            repeat{
    #                                fake.co <- sample(co, Nco, replace=TRUE)
    #                                fake.rev <- sample(rev, Nrev, replace=TRUE)
    #                                boot.id <- c(fake.rev, fake.co)
    #                                if (sum(apply(as.matrix(I[,boot.id]),1,sum)>=1)==TT) {
    #                                    break
    #                                }
    #                            }
    #                        } else {
    #                            repeat{
    #                                boot.id <- sample(rev, Nrev, replace=TRUE)
    #                                if (sum(apply(as.matrix(I[,boot.id]),1,sum)>=1)==TT) {
    #                                    break
    #                                }
    #                            }
    #                        }
    #                    }
    #                }
    #            } else {
    #                cl.boot <- sample(cl.unique, length(cl.unique), replace = TRUE)
    #                cl.boot.uni <- unique(cl.boot)
    #                cl.boot.count <- as.numeric(table(cl.boot))
    #                boot.id <- c()
    #                for (kk in 1:length(cl.boot.uni)) {
    #                    boot.id <- c(boot.id, rep(which(cl == cl.boot.uni[kk]), cl.boot.count[kk]))
    #                }
    #            }

    #        } else {
    #            boot.id <- 1:N
    #            boot.id <- boot.id[-num]
    #        }
            
            
                
    #        X.boot <- X[,boot.id,,drop = FALSE]
    #        D.boot <- D[, boot.id]
    #        I.boot <- I[, boot.id]

    #        if (sum(c(D.boot) == 0) == 0 | sum(c(D.boot) == 1) == 0 | sum(c(I.boot) == 1) == 0) {
    #            boot0 <- list(att.avg = NA, att = NA, count = NA, 
    #                          beta = NA, att.off = NA, count.off = NA, 
    #                          att.placebo = NA)
    #            return(boot0)
    #        } else {
    #            T.off.boot <- NULL
    #            if (hasRevs == TRUE) {
    #                T.off.boot <- T.off[, boot.id]
    #            }
    #            placebo.period.boot <- NULL
    #            if (placeboTest == TRUE) {
    #                placebo.period.boot <- placebo.period
    #            }
                
    #            boot <- try(fect.mc(Y = Y[,boot.id], X = X.boot, D = D[,boot.id],
    #                                I = I[,boot.id], II = II[,boot.id],
    #                                T.on = T.on[,boot.id], T.off = T.off.boot, 
    #                                lambda.cv = out$lambda.cv, force = force, 
    #                                hasF = out$validF, hasRevs = hasRevs, 
    #                                tol = tol, boot = 1,
    #                                norm.para = norm.para,
    #                                time.on.seq = time.on, time.off.seq = time.off,
    #                                placebo.period = placebo.period.boot, 
    #                                placeboTest = placeboTest), silent = TRUE)
                
    #            if ('try-error' %in% class(boot)) {
    #                boot0 <- list(att.avg = NA, att = NA, count = NA, 
    #                              beta = NA, att.off = NA, count.off = NA, 
    #                              att.placebo = NA)
    #                return(boot0)
    #            } else {
    #                return(boot)
    #            }
    #        }                        
    #    } 
    #}

    ## jack.seq <- sample(1:N, N, replace = FALSE)
    boot.seq <- NULL
    if (vartype == "jackknife") {
        ## nboots <- min(N, nboots)
        ## boot.seq <- jack.seq[1:nboots]
        boot.seq <- 1:N 
    }
    
    ## computing
    if (parallel == TRUE) { 
        boot.out <- foreach(j=1:nboots, 
                            .inorder = FALSE,
                            .export = c("fect.fe", "fect.mc", "fect.polynomial", "get_term"),
                            .packages = c("fect")
                            ) %dopar% {
                                return(one.nonpara(boot.seq[j]))
                            }

        for (j in 1:nboots) { 
            att.avg.boot[,j] <- boot.out[[j]]$att.avg
            att.avg.unit.boot[, j] <- boot.out[[j]]$att.avg.unit
            att.on.boot[,j] <- boot.out[[j]]$att
            att.on.count.boot[,j] <- boot.out[[j]]$count
            if (p > 0) {
                beta.boot[,j] <- boot.out[[j]]$beta
            }
            if (hasRevs == 1) {
                att.off.boot[,j] <- boot.out[[j]]$att.off
                att.off.count.boot[,j] <- boot.out[[j]]$count.off 
            }
            if (!is.null(placebo.period) & placeboTest == TRUE) {
                att.placebo.boot[,j] <- boot.out[[j]]$att.placebo
            }
            if (!is.null(group)) {
                group.att.boot[,j] <- boot.out[[j]]$group.att
            }
        } 
    } else {
        for (j in 1:nboots) { 
            boot <- one.nonpara(boot.seq[j]) 
            att.avg.boot[,j] <- boot$att.avg
            att.avg.unit.boot[,j] <- boot$att.avg.unit
            att.on.boot[,j] <- boot$att
            att.on.count.boot[,j] <- boot$count
            if (p > 0) {
                beta.boot[,j] <- boot$beta
            }
            if (hasRevs == 1) {
                att.off.boot[,j] <- boot$att.off
                att.off.count.boot[,j] <- boot$count.off 
            }
            if (!is.null(placebo.period) & placeboTest == TRUE) {
                att.placebo.boot[,j] <- boot$att.placebo
            }
            if (!is.null(group)) {
                group.att.boot[,j] <- boot$group.att
            }
            ## report progress
            if (j%%100 == 0)  {
                cat(".")   
            }  
        }  
    } 
    ## end of bootstrapping
    
    ## remove failure bootstrap
    ## alternative condition? max(apply(is.na(att.on.boot),2,sum)) == dim(att.on.boot)[1]
    if (sum(is.na(c(att.avg.boot))) > 0) {
        boot.rm <- which(is.na(c(att.avg.boot)))
        att.avg.boot <- t(as.matrix(att.avg.boot[,-boot.rm]))
        att.avg.unit.boot <- t(as.matrix(att.avg.unit.boot[,-boot.rm]))
        att.on.boot <- as.matrix(att.on.boot[,-boot.rm])
        att.on.count.boot <- as.matrix(att.on.count.boot[,-boot.rm])
        if (p > 0) {
            beta.boot <- as.matrix(beta.boot[,-boot.rm])
            if (dim(beta.boot)[2] == 1) {
                beta.boot <- t(beta.boot)
            }
        }
        if (hasRevs == 1) {
            att.off.boot <- as.matrix(att.off.boot[,-boot.rm])
            att.off.count.boot <- as.matrix(att.off.count.boot[,-boot.rm])
        }
        if (!is.null(placebo.period) & placeboTest == TRUE) {
            att.placebo.boot <- t(as.matrix(att.placebo.boot[,-boot.rm]))
        }
        if (!is.null(group)) {
            if (dim(group.att.boot) == 1) {
                group.att.boot <- t(as.matrix(group.att.boot[, -boot.rm]))
            } else {
                group.att.boot <- as.matrix(group.att.boot[, -boot.rm])
            }
            
        }

    }
    cat(dim(att.on.boot)[2], " runs\n", sep = "")
     
    ####################################
    ## Variance and CIs
    ####################################

    ## function to get two-sided p-values
    get.pvalue <- function(vec) {
        if (NaN%in%vec|NA%in%vec) {
            nan.pos <- is.nan(vec)
            na.pos <- is.na(vec)
            pos <- c(which(nan.pos),which(na.pos))
            vec.a <- vec[-pos]
            a <- sum(vec.a >= 0)/(length(vec)-sum(nan.pos|na.pos)) * 2
            b <- sum(vec.a <= 0)/(length(vec)-sum(nan.pos|na.pos)) * 2  
        } else {
            a <- sum(vec >= 0)/length(vec) * 2
            b <- sum(vec <= 0)/length(vec) * 2  
        }
        return(min(as.numeric(min(a, b)),1))
    }

    ## ATT estimates
    if (vartype == "jackknife") {
        
        att.on.j <- jackknifed(att.on, att.on.boot, alpha)
        est.att.on <- cbind(att.on, att.on.j$se, att.on.j$CI.l, att.on.j$CI.u, att.on.j$P, out$count)
        colnames(est.att.on) <- c("ATT", "S.E.", "CI.lower", "CI.upper",
                                  "p.value", "count.on")
        rownames(est.att.on) <- out$time

        att.bound <- cbind(att.on + qnorm(alpha)*att.on.j$se, att.on + qnorm(1 - alpha)*att.on.j$se)
        colnames(att.bound) <- c("CI.lower", "CI.upper")
        rownames(att.bound) <- out$time

        if (hasRevs == 1) {
            att.off.j <- jackknifed(att.off, att.off.boot, alpha)
            est.att.off <- cbind(att.off, att.off.j$se, att.off.j$CI.l, att.off.j$CI.u, att.off.j$P, out$count.off)
            colnames(est.att.off) <- c("ATT.OFF", "S.E.", "CI.lower", "CI.upper",
                                      "p.value", "count.off")
            rownames(est.att.off) <- out$time.off

            att.off.bound <- cbind(att.off + qnorm(alpha)*att.off.j$se, att.off + qnorm(1 - alpha)*att.off.j$se)
            colnames(att.off.bound) <- c("CI.lower", "CI.upper")
            rownames(att.off.bound) <- out$time.off
        }

        ## average (over time) ATT
        att.avg.j <- jackknifed(att.avg, att.avg.boot, alpha)
        est.avg <- t(as.matrix(c(att.avg, att.avg.j$se, att.avg.j$CI.l, att.avg.j$CI.u, att.avg.j$P)))
        colnames(est.avg) <- c("ATT.avg", "S.E.", "CI.lower", "CI.upper", "p.value")

        att.avg.unit.j <- jackknifed(att.avg.unit, att.avg.unit.boot, alpha)
        est.avg.unit <- t(as.matrix(c(att.avg.unit, att.avg.unit.j$se, att.avg.unit.j$CI.l, att.avg.unit.j$CI.u, att.avg.unit.j$P)))
        colnames(est.avg.unit) <- c("ATT.avg.unit", "S.E.", "CI.lower", "CI.upper", "p.value")

        ## regression coefficents
        if (p > 0) {
            beta.j <- jackknifed(beta, beta.boot, alpha)
            est.beta <- cbind(beta, beta.j$se, beta.j$CI.l, beta.j$CI.u, beta.j$P)
            colnames(est.beta)<-c("beta", "S.E.", "CI.lower", "CI.upper", "p.value")
        }

        ## placebo test
        if (!is.null(placebo.period) & placeboTest == TRUE) {
            att.placebo <- out$att.placebo
            att.placebo.j <- jackknifed(att.placebo, att.placebo.boot, alpha)
            est.placebo <- t(as.matrix(c(att.placebo, att.placebo.j$se, att.placebo.j$CI.l, att.placebo.j$CI.u, att.placebo.j$P)))
            colnames(est.placebo) <- c("ATT.placebo", "S.E.", "CI.lower", "CI.upper", "p.value")
        }

        ## cohort effect
        if (!is.null(group)) {
            group.att.j <- jackknifed(group.att, group.att.boot, alpha)

            est.group.att <- cbind(group.att, group.att.j$se, group.att.j$CI.l, group.att.j$CI.u, group.att.j$P)
            
            colnames(est.group.att) <- c("ATT", "S.E.", "CI.lower", "CI.upper",
                                         "p.value")
        }

    } else {

        CI.att.on <- t(apply(att.on.boot, 1, function(vec) quantile(vec,c(alpha/2, 1 - alpha/2), na.rm=TRUE)))
        se.att.on <- apply(att.on.boot, 1, function(vec) sd(vec, na.rm=TRUE))
        pvalue.att.on <- apply(att.on.boot, 1, get.pvalue)

        est.att.on <- cbind(att.on, se.att.on, CI.att.on, pvalue.att.on, out$count)
        colnames(est.att.on) <- c("ATT", "S.E.", "CI.lower", "CI.upper",
                                  "p.value", "count.on")
        rownames(est.att.on) <- out$time
        #T0.on.l <- sum(out$time.on <= 0)
        #norm.att.on.sq <- (att.on/se.att.on)^2
        #T0.on.p <- 1 - pchisq(sum(norm.att.on.sq[1:T0.on.l]), df = T0.on.l)

        att.bound <- t(apply(att.on.boot, 1, function(vec) quantile(vec,c(alpha, 1 - alpha), na.rm=TRUE)))
        colnames(att.bound) <- c("CI.lower", "CI.upper")
        rownames(att.bound) <- out$time
        

        if (hasRevs == 1) {
            CI.att.off <- t(apply(att.off.boot, 1, function(vec) quantile(vec,c(alpha/2, 1 - alpha/2), na.rm=TRUE)))
            se.att.off <- apply(att.off.boot, 1, function(vec) sd(vec, na.rm=TRUE))
            pvalue.att.off <- apply(att.off.boot, 1, get.pvalue)

            est.att.off <- cbind(att.off, se.att.off, CI.att.off, pvalue.att.off, out$count.off)
            colnames(est.att.off) <- c("ATT.OFF", "S.E.", "CI.lower", "CI.upper",
                                       "p.value", "count.off")
            rownames(est.att.off) <- out$time.off
            #T0.off.l <- sum(out$time.off > 0)
            #norm.att.off.sq <- (att.off/se.att.off)^2
            #T0.off.p <- 1 - pchisq(sum(norm.att.off.sq[(length(out$time.off) - T0.off.l + 1):length(out$time.off)]), df = T0.off.l)

            att.off.bound <- t(apply(att.off.boot, 1, function(vec) quantile(vec,c(alpha, 1 - alpha), na.rm=TRUE)))
            colnames(att.off.bound) <- c("CI.lower", "CI.upper")
            rownames(att.off.bound) <- out$time.off
        }

        ## average (over time) ATT
        CI.avg <- quantile(att.avg.boot, c(alpha, 1 - alpha/2), na.rm=TRUE)
        se.avg <- sd(att.avg.boot, na.rm=TRUE)
        pvalue.avg <- get.pvalue(att.avg.boot)
        est.avg <- t(as.matrix(c(att.avg, se.avg, CI.avg, pvalue.avg)))
        colnames(est.avg) <- c("ATT.avg", "S.E.", "CI.lower", "CI.upper", "p.value")


        CI.avg.unit <- quantile(att.avg.unit.boot, c(alpha, 1 - alpha/2), na.rm=TRUE)
        se.avg.unit <- sd(att.avg.unit.boot, na.rm=TRUE)
        pvalue.avg.unit <- get.pvalue(att.avg.unit.boot)
        est.avg.unit <- t(as.matrix(c(att.avg.unit, se.avg.unit, CI.avg.unit, pvalue.avg.unit)))
        colnames(est.avg.unit) <- c("ATT.avg.unit", "S.E.", "CI.lower", "CI.upper", "p.value")

        
        ## regression coefficents
        if (p > 0) {
            CI.beta<-t(apply(beta.boot, 1, function(vec)
                quantile(vec,c(alpha/2, 1 - alpha/2), na.rm=TRUE)))
            se.beta<-apply(beta.boot, 1, function(vec)sd(vec,na.rm=TRUE))
            pvalue.beta <- apply(beta.boot, 1, get.pvalue)
            beta[na.pos] <- NA
            est.beta<-cbind(beta, se.beta, CI.beta, pvalue.beta)
            colnames(est.beta)<-c("beta", "S.E.", "CI.lower", "CI.upper", "p.value")
        }

        ## placebo test
        if (!is.null(placebo.period) & placeboTest == TRUE) {
            att.placebo <- out$att.placebo        
            CI.placebo <- quantile(att.placebo.boot, c(alpha/2, 1- alpha/2), na.rm=TRUE)
            se.placebo <- sd(att.placebo.boot, na.rm=TRUE)
            pvalue.placebo <- get.pvalue(att.placebo.boot)
            est.placebo <- t(as.matrix(c(att.placebo, se.placebo, CI.placebo, pvalue.placebo)))
            colnames(est.placebo) <- c("ATT.placebo", "S.E.", "CI.lower", "CI.upper", "p.value")
        }

    }
  
    ##storage
    result<-list(est.avg = est.avg,
                 att.avg.boot = att.avg.boot,
                 est.avg.unit = est.avg.unit,
                 att.avg.unit.boot = att.avg.unit.boot,
                 est.att = est.att.on,
                 att.bound = att.bound,
                 att.boot = att.on.boot,
                 att.count.boot = att.on.count.boot)

    if (p>0) {
        result <- c(result,list(beta.boot = beta.boot))
        result <- c(result,list(est.beta = est.beta))
    }
    if (hasRevs == 1) {
        result<-c(result,list(est.att.off = est.att.off, 
                              att.off.boot = att.off.boot, 
                              att.off.bound = att.off.bound,
                              att.off.count.boot = att.off.count.boot))
    } 

    if (!is.null(placebo.period) & placeboTest == TRUE) {
        result <- c(result, list(est.placebo = est.placebo, att.placebo.boot = att.placebo.boot))
    }

    if (!is.null(group)) {
        result <- c(result, list(est.group.att = est.group.att))

    }

    return(c(out,result))

    
} ## end of boot


## jackknife se
jackknifed <- function(x,  ## ols estimates
                       y,
                       alpha) { ## sub-sample ols estimates) 

    p <- length(x)
    N <- dim(y)[2]  ## sample size

    X <- matrix(rep(c(x), N), p, N) * N
    Y <- X - y * (N - 1)

    Yvar <- apply(Y, 1, var, na.rm = TRUE)
    vn <- N - apply(is.na(y), 1, sum) 

    Ysd <- sqrt(Yvar/vn)  ## jackknife se

    CI.l <- Ysd * qnorm(alpha/2) + c(x)
    CI.u <- Ysd * qnorm(1 - alpha/2) + c(x)

    ## wald test
    P <- NULL
    for (i in 1:p) {
        subz <- pnorm(c(x)[i]/Ysd[i])
        P <- c(P, 2 * min(1 - subz, subz))
    }

    ## P <- 2 * min(1 - pnorm(c(x)/Ysd), pnorm(c(x)/Ysd))

    out <- list(se = Ysd, CI.l = CI.l, CI.u = CI.u, P = P)

    return(out)
    
}