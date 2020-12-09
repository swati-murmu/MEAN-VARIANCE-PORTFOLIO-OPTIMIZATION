# Connect to PostgreSQL ---------------------------------------------------

# Make sure you have created the reader role for our PostgreSQL database
# and granted that role SELECT rights to all tables
# Also, make sure that you have completed (or restored) Part 3b db
# Stock Market Case in R
rm(list=ls(all=T)) # this just removes everything from memory


require(RPostgreSQL) # did you install this package?
require(DBI)
pg = dbDriver("PostgreSQL")
conn = dbConnect(drv=pg
                 ,user="stockmarketreader"
                 ,password="read123"
                 ,host="localhost"
                 ,port=5432
                 ,dbname="stockmarket"
)

#custom calendar
qry="SELECT * FROM custom_calendar WHERE date BETWEEN '2012-12-31' AND '2018-03-31' ORDER by date"
ccal<-dbGetQuery(conn,qry)
#eod prices and indices
qry1="SELECT symbol,date,adj_close FROM eod_indices WHERE date BETWEEN '2012-12-31' AND '2018-03-31'"
qry2="SELECT ticker,date,adj_close FROM eod_quotes WHERE date BETWEEN '2012-12-31' AND '2018-03-31'"
eod<-dbGetQuery(conn,paste(qry1,'UNION',qry2))
dbDisconnect(conn)

#Explore
head(ccal)
tail(ccal)
nrow(ccal)


head(eod)
tail(eod)
nrow(eod)

head(eod[which(eod$symbol=='SP500TR'),])

# Use Calendar --------------------------------------------------------

tdays<-ccal[which(ccal$trading==1),,drop=F]
head(tdays)
nrow(tdays)-1

# Completeness ----------------------------------------------------------
# Percentage of completeness
pct<-table(eod$symbol)/(nrow(tdays)-1)
selected_symbols_daily<-names(pct)[which(pct>=0.99)]
eod_complete<-eod[which(eod$symbol %in% selected_symbols_daily),,drop=F]

#check
head(eod_complete)
tail(eod_complete)
nrow(eod_complete)

# Transform (Pivot) -------------------------------------------------------

require(reshape2) #did you install this package?
eod_pvt<-dcast(eod_complete, date ~ symbol,value.var='adj_close',fun.aggregate = mean, fill=NULL)
#check
eod_pvt[1:10,1:5] #first 10 rows and first 5 columns 
ncol(eod_pvt) # column count
nrow(eod_pvt)

# Merge with Calendar -----------------------------------------------------
eod_pvt_complete<-merge.data.frame(x=tdays[,'date',drop=F],y=eod_pvt,by='date',all.x=T)

#check
eod_pvt_complete[1:10,1:5] #first 10 rows and first 5 columns 
ncol(eod_pvt_complete)
nrow(eod_pvt_complete)

#use dates as row names and remove the date column
rownames(eod_pvt_complete)<-eod_pvt_complete$date
eod_pvt_complete$date<-NULL

#re-check
eod_pvt_complete[1:10,1:5] #first 10 rows and first 5 columns 
ncol(eod_pvt_complete)
nrow(eod_pvt_complete)

# Missing Data Imputation -----------------------------------------------------
# We can replace a few missing (NA or NaN) data items with previous data
# Let's say no more than 3 in a row...
require(zoo)
eod_pvt_complete<-na.locf(eod_pvt_complete,na.rm=F,fromLast=F,maxgap=3)
#re-check
eod_pvt_complete[1:10,1:5] #first 10 rows and first 5 columns 
ncol(eod_pvt_complete)
nrow(eod_pvt_complete)

# Calculating Returns -----------------------------------------------------
require(PerformanceAnalytics)
eod_ret<-CalculateReturns(eod_pvt_complete)
#check
eod_ret[1:10,1:4] #first 10 rows and first 4 columns 
ncol(eod_ret)
nrow(eod_ret)

#remove the first row
eod_ret<-tail(eod_ret,-1) #use tail with a negative value
#check
eod_ret[1:10,1:4] #first 10 rows and first 4 columns 
ncol(eod_ret)
nrow(eod_ret)

# Check for extreme returns -------------------------------------------
# There is colSums, colMeans but no colMax so we need to create it
colMax <- function(data) sapply(data, max, na.rm = TRUE)
# Apply it
max_daily_ret<-colMax(eod_ret)
max_daily_ret[1:10] #first 10 max returns
# And proceed just like we did with percentage (completeness)
selected_symbols_daily<-names(max_daily_ret)[which(max_daily_ret<=1.00)]
length(selected_symbols_daily)

#subset eod_ret
eod_ret<-eod_ret[,which(colnames(eod_ret) %in% selected_symbols_daily)]
#check
eod_ret[1:10,1:4] #first 10 rows and first 4 columns 
ncol(eod_ret)
nrow(eod_ret)

# Export data from R to CSV -----------------------------------------------
write.csv(eod_ret,'C:/Users/navee/Dropbox (CSU Fullerton)/ISDS 570/Project/eod_ret.csv')

# Tabular Return Data Analytics -------------------------------------------

# We will select 'SP500TR' and c('MAN','MAR','MAT','KALU','KAMN','KAR','MSFT','MET','MCD','RAS','RAIL','RAD','KBH','KBR','KEG')
# We need to convert data frames to xts (extensible time series)
Ra<-as.xts(eod_ret[,c('MAN','MAR','MAT','KALU','KAMN','KAR','MSFT','MET','MCD','RAS','RAIL',
                      'RAD','KBH','KBR','KEG'),drop=F])
Rb<-as.xts(eod_ret[,'SP500TR',drop=F]) #benchmark

head(Ra)
head(Rb)

# And now we can use the analytical package...

# Returns
table.AnnualizedReturns(cbind(Rb,Ra),scale=252) # note for monthly use scale=12

# Accumulate Returns
acc_Ra<-Return.cumulative(Ra)
acc_Rb<-Return.cumulative(Rb)

# Use this data in Tableau to generate better graphs for Question 1
write.csv(acc_Ra,'C:/Users/navee/Dropbox (CSU Fullerton)/ISDS 570/Project/CumReturnsTickers.csv')
write.csv(acc_Rb,'C:/Users/navee/Dropbox (CSU Fullerton)/ISDS 570/Project/CumReturnsIndex.csv')

# Graphical Return Data Analytics -----------------------------------------

# Cumulative returns chart - Question number 1
chart.CumReturns(Ra,main ='Cumulative Returns chart for the selected tickers',
                 xlab='Period',ylab='Returns',legend.loc = 'topleft')
chart.CumReturns(Rb,main ='Cumulative Returns chart for SP500TR',
                 xlab='Period',ylab='Returns',legend.loc = 'topleft')


# MV Portfolio Optimization -----------------------------------------------

# withold the data upto 2017 trading days
Ra_training<-head(Ra,-59)
Rb_training<-head(Rb,-59)

# use the 2018 trading days for testing
Ra_testing<-tail(Ra,59)
Rb_testing<-tail(Rb,59)


#optimize the MV (Markowitz 1950s) portfolio weights based on training
table.AnnualizedReturns(Rb_training)
mar<-mean(Rb_training) #we need daily minimum acceptabe return

require(PortfolioAnalytics)
require(ROI) # make sure to install it
require(ROI.plugin.quadprog)  # make sure to install it
pspec<-portfolio.spec(assets=colnames(Ra_training))
pspec<-add.objective(portfolio=pspec,type="risk",name='StdDev')
pspec<-add.constraint(portfolio=pspec,type="full_investment")
pspec<-add.constraint(portfolio=pspec,type="return",return_target=mar)

#optimize portfolio - can modify the optimization method to see various results as well
opt_p<-optimize.portfolio(R=Ra_training,portfolio=pspec,optimize_method = 'ROI')

#extract weights
opt_w<-opt_p$weights # Question number 2
write.csv(opt_w,'C:/Users/navee/Dropbox (CSU Fullerton)/ISDS 570/Project/Weights.csv')

#apply weights to test returns
Rp<-Rb_testing # easier to apply the existing structure
#define new column that is the dot product of the two vectors
Rp$ptf<-Ra_testing %*% opt_w

#check
head(Rp)
tail(Rp)

#Compare basic metrics - Question number 4
table.AnnualizedReturns(Rp) 

# Use this data in Tableau to generate better graphs for Question 1
write.csv(Rp,'C:/Users/navee/Dropbox (CSU Fullerton)/ISDS 570/Project/PredPortfolioRet.csv')

# Chart Hypothetical Portfolio Returns -Question number 3
chart.CumReturns(Rp,main='', xlab='Period',ylab='Returns',legend.loc = 'topleft')

# End of Stock Market Case Study 