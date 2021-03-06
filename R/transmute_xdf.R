#' @include mutate_xdf.R
NULL


#' @rdname mutate
#' @export
transmute_.RxFileData <- function(.data, ..., .outFile, .rxArgs, .dots)
{
    dots <- lazyeval::all_dots(.dots, ..., all_named=TRUE)

    # .outFile and .rxArgs will be passed in via .dots if called by NSE
    dots <- rxArgs(dots)
    exprs <- dots$exprs
    if(missing(.outFile)) .outFile <- dots$output
    if(missing(.rxArgs)) .rxArgs <- dots$rxArgs

    if(any(sapply(exprs, is.null)))
        stop("do not set variables to NULL in transmute; to delete variables, leave them out of the function call")

    .outFile <- createOutput(.data, .outFile)
    transmute_base(.data, .outFile, exprs, .rxArgs)
}


#' @rdname mutate
#' @export
transmute_.grouped_tbl_xdf <- function(.data, ..., .outFile, .rxArgs, .dots)
{
    stopIfHdfs(.data, "transmute on grouped data not supported on HDFS")

    dots <- lazyeval::all_dots(.dots, ..., all_named=TRUE)

    # .outFile and .rxArgs will be passed in via .dots if called by NSE
    dots <- rxArgs(dots)
    exprs <- dots$exprs
    if(missing(.outFile)) .outFile <- dots$output
    if(missing(.rxArgs)) .rxArgs <- dots$rxArgs

    grps <- groups(.data)
    if(any(sapply(exprs, is.null)))
        stop("do not set variables to NULL in transmute; to delete variables, leave them out of the function call")
    if(any(names(exprs) %in% grps))
        stop("cannot transmute grouping variable")

    xdflst <- split_groups(.data)
    outlst <- createSplitOutput(xdflst, .outFile)
    outlst <- rxExec(transmute_base, data=rxElemArg(xdflst), output=rxElemArg(outlst), exprs, .rxArgs, grps,
        execObjects="deleteTbl", packagesToLoad="dplyrXdf")
    combine_groups(outlst, createOutput(.data, .outFile), grps)
}


transmute_base <- function(data, output, exprs, rxArgs=NULL, gvars=NULL, tblDir=getXdfTblDir())
{
    oldData <- data
    if(hasTblFile(data))
        on.exit(deleteTbl(oldData))

    # identify variables to drop
    if(!is.null(rxArgs$transformFunc))  # first case: transformFunc is present
    {
        # pad out transformVars parameter with all variables in dataset (excluding grouping variables)
        # this will force rxDataStep to drop vars not returned from transformFunc
        dropvars <- setdiff(union(names(data), names(exprs)), gvars)
        rxArgs$transformVars <- dropvars
    }
    else  # second case: no transformFunc
    {
        # set variables to NULL to drop them
        dropvars <- setdiff(names(data), c(names(exprs), gvars))
        exprs[dropvars] <- list(NULL)
    }

    exprlst <- if(length(exprs) > 0)
        as.call(c(quote(list), exprs))
    else NULL

    cl <- substitute(rxDataStep(data, output, transforms=.expr, overwrite=TRUE),
        list(.expr=exprlst))
    cl[names(rxArgs)] <- rxArgs

    eval(cl)
}

