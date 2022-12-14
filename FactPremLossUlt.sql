/* RUN STAGE_DimMonth FIRST!!!!!!!!!!!!!! */



--Create table version of the view ******************************************************************************************************************************************************
drop table if exists work.FactLoss_Cap
select *
into Product_Work.work.FactLoss_Cap
from Product_Work.dbo.vw_FactLoss_Cap (nolock)

create clustered columnstore index ccix on Product_Work.work.FactLoss_Cap

drop table if exists work.FactLossCal_Cap
select *
into Product_Work.work.FactLossCal_Cap
from Product_Work.dbo.vw_FactLossCal_Cap (nolock)

create clustered columnstore index ccix on Product_Work.work.FactLossCal_Cap
--Create table version of the view ******************************************************************************************************************************************************


/* Curr LOSS ACCIDENT *************************************************************************************************************************************************************************/
/* Only updated when Actuary publishes APLD */
declare @CurrAccYearMo as int = (select max(FiscalYearMonth) from work.STAGE_DimMonth where T12Ind_IL=1)
print @CurrAccYearMo
drop table if exists work.STAGE_FactLossAcc_Curr
select
	flc_cap.PolicyKey
	,flc_cap.RiskKey
	,flc_cap.CoverageKey
	,flc_cap.DoLMonthTimeKey
	,flc_cap.CededCoverageInd

	,cast( dp.planCode as varchar(5) ) as planCode
	,cast( lkpFirm.Grp1 as varchar(6) ) as firm_APLD
	,cast( lkpChannel.Grp1 as varchar(1) ) as distChannel_APLD
	,cast( case when lkpProdVer.Grp1 is null then 'XX' else lkpProdVer.Grp1 end as varchar(2) ) as prodVer_APLD
	
	,cast( case when lkpLOB.Grp1 is null then dp.Product else lkpLOB.Grp1 end as varchar(7) ) as LOB_APLD
	,cast( apld.cov_APLD as varchar(10) ) as cov_APLD
	,cast( apld.LDFcov_APLD as varchar(10) ) as LDFcov_APLD
  	,cast( 
	case 
		when dp.Product='PPA' and dp.GoverningState='NC' and (dp.NCRatingTier in ('Preferred','UltraPreferred') or dp.CustomerGroup='PRF') then 'NCPF'
		when dp.Product='PPA' and dp.GoverningState='NC' then 'NCNS'
		else dp.GoverningState
	end as varchar(6) ) as State_APLD

	--,cast( SUM(flc_cap.IL) as decimal(18,2) ) as IL_Acc
	,cast( SUM(flc_cap.IL_Cap) as decimal(18,2) ) as IL_Acc_Cap 
	,cast( SUM(flc_cap.catIL) as decimal(18,2) ) as catIL_Acc_Cap 
	--,cast( SUM(flc_cap.IL_xLL_Cap) as decimal(18,2) ) as IL_xLL_Acc_Cap 
	--,cast( SUM(flc_cap.IL_cap50kLL_Cap) as decimal(18,2) ) as IL_cap50kLL_Acc_Cap 
	--,cast( SUM(flc_cap.IL_cap100kLL_Cap) as decimal(18,2) ) as IL_cap100kLL_Acc_Cap 

	,sum(case when flc_cap.IL_Cap >= 50000 then 0 else flc_cap.IL_Cap end) as IL_xLL_Acc_Cap
	,sum(case when flc_cap.IL_Cap >= 50000 then 50000 else flc_cap.IL_Cap end) as IL_cap50kLL_Acc_Cap
	,sum(case when flc_cap.IL_Cap >= 100000 then 100000 else flc_cap.IL_Cap end) as IL_cap100kLL_Acc_Cap

	,cast( SUM(flc_cap.PaidLoss_Cap) as decimal(18,2) ) as PaidLoss_Cap
	--,sum(flc_cap.Sal) as Sal
	--,sum(flc_cap.Sub) as Sub
	--,sum(flc_cap.LCR) as LCR
	--,sum(flc_cap.CurrResAmt) as CurrResAmt
	--,sum(flc_cap.PriorResAmt) as PriorResAmt
	,SUM(flc_cap.netFeature) as netFeature
	,sum(case 
			when dc.SourceCoverageCode in ('Unknown','BISSL') then 0
			when flc_cap.ClaimCoverageCode in ('PDR','PIB','PIL','PIP','PIF','PIES') then 0
			when flc_cap.ClaimCoverageDescription in ('UOBI','UOCL','UOMP','UONF','UOPD') then 0		
			else flc_cap.NetFeature
	end) as NetFeature_Curr_APLD

into Product_Work.work.STAGE_FactLossAcc_Curr

from 
--Product_Work.dbo.vw_FactLossCal_Cap as flc_cap with (nolock)
Product_Work.work.FactLossCal_Cap as flc_cap

	inner join AnalyticsDataHub.dbo.DimPolicy as dp with (nolock)
			on flc_cap.PolicyKey = dp.PolicyKey 
			and dp.firmID not in ('32','34','39')
			and flc_cap.DoLMonthTimeKey >= (select min(FiscalYearMonth) from work.STAGE_DimMonth where T60Ind_Fisc=1)
			and flc_cap.RefCalPerMonthKeyId <= @CurrAccYearMo
			--and dp.GoverningState in ('NY') and dp.product = 'PPA'
			--and flc_cap.DoLMonthTimeKey >= 202001
    inner join AnalyticsDataHub.dbo.DimRisk as dr with (nolock)
			on flc_cap.RiskKey = dr.RiskKey
	inner join AnalyticsDataHub.dbo.DimCoverage as dc with (nolock)
			on flc_cap.CoverageKey = dc.CoverageKey

	left join Product_Work.tpu.lkpMaster as lkpFirm on lkpFirm.lkpType = 'APLD_FIRM' and lkpFirm.lkpItem = dp.FirmId
	left join Product_Work.tpu.lkpMaster as lkpChannel on lkpChannel.lkpType = 'APLD_CHANNEL' and lkpChannel.lkpItem = dp.DistributionChannel
	left join Product_Work.tpu.lkpMaster as lkpProdVer on lkpProdVer.lkpType = 'APLD_PROD_VER' and lkpProdVer.lkpItem = dp.ProductVersion
	left join Product_Work.tpu.lkpMaster as lkpLOB on lkpLOB.lkpType = 'APLD_LOB' and lkpLOB.lkpItem = dr.RiskSubType

	left join Product_Work.tpu.CovMapADHtoAPLD as apld on
			apld.adh_sourceCovCode = 
				(case 
						when dc.SourceCoverageCode='Unknown' and flc_cap.EPICcoverageCode='NA' then flc_cap.ClaimCoverageCode
						when dc.SourceCoverageCode='Unknown' and flc_cap.EPICcoverageCode<>'NA' then flc_cap.EPICcoverageCode
						else dc.SourceCoverageCode 
				end) 
			and apld.lob_apld = 
				(case 
						when dr.RiskSubType in ('BOOM','DUMP','FBTK','HOPP','FTPU','MITK','ROV','SPDE','SBTK','STVN','STRT','TNTK','FTTR','EUTR','OUTR','HTFR','DBUR','FBUR','BUTR','LBUR','LSTR','GNTR','BCTR','DFTR','DBTR','FBTR','LVTR','LBTR','POTR','RTTR','TNTR','TLTR')  then 'FV'
						when dr.RiskSubType in ('AIRS','BUSC','CABE','CAMP', 'MOTO','SEMI','TRAI','VANC','CMTP','CTHR','DMOT','FTHR','HTLQ','AMOT','CMOT','TTCO','FWTT','PCTT','BMOT','TOTR') then 'RV'
						else dp.Product
				end)
			and apld.state_apld = 
				(case
							when dp.GoverningState='NC' and (dp.NCRatingTier in ('Preferred','UltraPreferred') or dp.CustomerGroup='PRF') then 'NCPF'
							when dp.GoverningState='NC' then 'NCNS'
							else dp.GoverningState
				end)


group by
	flc_cap.PolicyKey
	,flc_cap.RiskKey
	,flc_cap.CoverageKey
	,flc_cap.DoLMonthTimeKey
	,flc_cap.CededCoverageInd

	,cast( dp.planCode as varchar(5) ) 
	,cast( lkpFirm.Grp1 as varchar(6) ) 
	,cast( lkpChannel.Grp1 as varchar(1) ) 
	,cast( case when lkpProdVer.Grp1 is null then 'XX' else lkpProdVer.Grp1 end as varchar(2) ) 
	,cast( case when lkpLOB.Grp1 is null then dp.Product else lkpLOB.Grp1 end as varchar(7) ) 
	,cast( apld.cov_APLD as varchar(10) ) 
	,cast( apld.LDFcov_APLD as varchar(10) ) 
  	,cast( case 
		when dp.Product='PPA' and dp.GoverningState='NC' and (dp.NCRatingTier in ('Preferred','UltraPreferred') or dp.CustomerGroup='PRF') then 'NCPF'
		when dp.Product='PPA' and dp.GoverningState='NC' then 'NCNS'
		else dp.GoverningState
	end as varchar(6) ) 
Option (MaxDOP 0)
/* Curr LOSS ACCIDENT *************************************************************************************************************************************************************************/




select DoLMonthTimeKey, format(sum(IL_Acc_Cap),'C0'), format(sum(NetFeature),'N0'), format(sum(catIL_Acc_Cap),'C0') 
--select DoLMonthTimeKey, format(sum(IL_Cap),'C0'), format(sum(NetFeature),'N0') --, format(sum(NetFeature_Curr_APLD),'C0') 
--from Product_Work.work.JS_Test
--from Product_Work.work.FactLossCal_Cap
from work.STAGE_FactLossAcc_Curr
--where LOB_APLD = 'PPA' and State_APLD = 'NY' 
group by DoLMonthTimeKey 
order by DoLMonthTimeKey desc


--select format(sum(IL_Acc_Cap),'C0') il_acc, format(sum(NetFeature),'N0') --, format(sum(NetFeature_Curr_APLD),'C0') 
--from work.STAGE_FactLossAcc_Curr
--where DoLMonthTimeKey=202104
----where LOB_APLD = 'PPA' and State_APLD = 'NY' 
----group by LOB_APLD 
--order by il_acc desc



--select DoLMonthTimeKey, format(sum(IL_Acc_Cap),'C0'), format(sum(NetFeature),'N0')
--	--format(sum(IL_xLL_Acc_Cap),'C0'), format(sum(IL_cap50kLL_Acc_Cap),'C0') , format(sum(IL_cap100kLL_Acc_Cap),'C0') ,
--	--format(sum(IL_xLL_Acc_Cap2),'C0'), format(sum(IL_cap50kLL_Acc_Cap2),'C0') , format(sum(IL_cap100kLL_Acc_Cap2),'C0') 
--from work.STAGE_FactLossAcc_Curr as a
--	inner join AnalyticsDataHub.dbo.DimPolicy as dp with (nolock)
--			on a.PolicyKey = dp.PolicyKey 
--			and dp.SourceSystemCode='NPS'
--			and a.cededCoverageInd=0
--where 
--a.LOB_APLD in ('PPA','CV','MC','RV','FV') 
--	and cov_APLD <> 'Excluded'
--group by DoLMonthTimeKey
--order by DoLMonthTimeKey desc



--select LOB_APLD, format(sum(IL_Acc_Cap),'C0'), format(sum(NetFeature),'C0') , format(sum(NetFeature_Curr_APLD),'C0') 
--from work.STAGE_FactLossAcc_Curr
--where State_APLD = 'NY' and DoLMonthTimeKey between 202001 and 202012
--group by LOB_APLD 


--select format(sum(IL_Acc_Cap),'C0') from work.STAGE_FactLossAcc_Curr
--where LOB_APLD = 'PPA' 
--and State_APLD = 'VA' and DoLMonthTimeKey between 202001 and 202012


--select DoLMonthTimeKey, format(sum(IL_Acc_Cap),'C0') 
--from work.STAGE_FactLossAcc_Curr
--where LOB_APLD = 'PPA' 
--and State_APLD = 'NY' and DoLMonthTimeKey between 202001 and 202012
--group by DoLMonthTimeKey
--order by DoLMonthTimeKey


declare @CurrYearMo as int = 202208
/* LOSS NON-NPS ACC PERIOD *************************************************************************************************************************************************************************/
/* Run monthly w fiscal month-end */
drop table if exists Product_Work.work.STAGE_FactLossAccNonNPSSys
select
	fl_cap.PolicyKey
	,fl_cap.RiskKey
	,fl_cap.CoverageKey
	,fl_cap.DOLMonthTimeKey
	,fl_cap.cededCoverageInd

	,cast( dp.planCode as varchar(5) ) as planCode
	,cast( lkpFirm.Grp1 as varchar(6) ) as firm_APLD
	,cast( lkpChannel.Grp1 as varchar(1) ) as distChannel_APLD
	,cast( case when lkpProdVer.Grp1 is null then 'XX' else lkpProdVer.Grp1 end as varchar(2) ) as prodVer_APLD
	,cast( case when lkpLOB.Grp1 is null then dp.Product else lkpLOB.Grp1 end as varchar(7) ) as LOB_APLD
	,cast( apld.cov_APLD as varchar(10) ) as cov_APLD
	,cast( apld.LDFcov_APLD as varchar(10) ) as LDFcov_APLD
  	,cast( case 
		when dp.Product='PPA' and dp.GoverningState='NC' and (dp.NCRatingTier in ('Preferred','UltraPreferred') or dp.CustomerGroup='PRF') then 'NCPF'
		when dp.Product='PPA' and dp.GoverningState='NC' then 'NCNS'
		else dp.GoverningState
	end as varchar(6) ) as State_APLD

	,cast(sum(fl_cap.PL_Cap) as decimal(18,2) ) as PaidLoss_Cap
	,cast( SUM(fl_cap.IL_Cap) as decimal(18,2) ) as IL_Acc_Cap
	,cast( SUM(fl_cap.catIL) as decimal(18,2) ) as catIL_Acc_Cap 
	,cast( SUM(fl_cap.IL_xLL_Cap) as decimal(18,2) ) as IL_xLL_Acc_Cap 
	,cast( SUM(fl_cap.IL_cap50kLL_Cap) as decimal(18,2) ) as IL_cap50kLL_Acc_Cap 
	,cast( SUM(fl_cap.IL_cap100kLL_Cap) as decimal(18,2) ) as IL_cap100kLL_Acc_Cap 
	,SUM(fl_cap.NetFeature) as NetFeature 
	,sum(case 
			when dc.SourceCoverageCode in ('Unknown','BISSL') then 0
			when fl_cap.ClaimCoverageCode in ('PDR','PIB','PIL','PIP','PIF','PIES') then 0
			when fl_cap.ClaimCoverageDescription in ('UOBI','UOCL','UOMP','UONF','UOPD') then 0		
			else fl_cap.NetFeature
	end) as NetFeature_Curr_APLD

into Product_Work.work.STAGE_FactLossAccNonNPSSys

--from Product_Work.dbo.vw_FactLoss_Cap as fl_cap with (nolock)
from Product_Work.work.FactLoss_Cap as fl_cap
	inner join AnalyticsDataHub.dbo.DimPolicy as dp with (nolock)
			on fl_cap.PolicyKey = dp.PolicyKey 
			and dp.firmID not in ('32','34','39')
			and fl_cap.DOLMonthTimeKey >= (select min(FiscalYearMonth) from work.STAGE_DimMonth where T60Ind_Fisc=1)
			and fl_cap.RefCalPerMonthKeyId <= @CurrYearMo
			--and dp.GoverningState in ('CA') and dp.product = 'PPA' and dp.CompanySegment = 'Traditional'
    inner join AnalyticsDataHub.dbo.DimRisk as dr with (nolock)
			on fl_cap.RiskKey = dr.RiskKey
	inner join AnalyticsDataHub.dbo.DimCoverage as dc with (nolock)
			on fl_cap.CoverageKey = dc.CoverageKey
	left join Product_Work.tpu.lkpMaster as lkpFirm on lkpFirm.lkpType = 'APLD_FIRM' and lkpFirm.lkpItem = dp.FirmId
	left join Product_Work.tpu.lkpMaster as lkpChannel on lkpChannel.lkpType = 'APLD_CHANNEL' and lkpChannel.lkpItem = dp.DistributionChannel
	left join Product_Work.tpu.lkpMaster as lkpProdVer on lkpProdVer.lkpType = 'APLD_PROD_VER' and lkpProdVer.lkpItem = dp.ProductVersion
	left join Product_Work.tpu.lkpMaster as lkpLOB on lkpLOB.lkpType = 'APLD_LOB' and lkpLOB.lkpItem = dr.RiskSubType
	left join Product_Work.tpu.CovMapADHtoAPLD as apld on
		apld.adh_sourceCovCode = 
			(case 
					when dc.SourceCoverageCode='Unknown' and fl_cap.EPICcoverageCode='NA' then fl_cap.ClaimCoverageCode
					when dc.SourceCoverageCode='Unknown' and fl_cap.EPICcoverageCode<>'NA' then fl_cap.EPICcoverageCode
					else dc.SourceCoverageCode 
			end) 
		and apld.lob_apld = 
			(case 
					when dr.RiskSubType in ('BOOM','DUMP','FBTK','HOPP','FTPU','MITK','ROV','SPDE','SBTK','STVN','STRT','TNTK','FTTR','EUTR','OUTR','HTFR','DBUR','FBUR','BUTR','LBUR','LSTR','GNTR','BCTR','DFTR','DBTR','FBTR','LVTR','LBTR','POTR','RTTR','TNTR','TLTR')  then 'FV'
					when dr.RiskSubType in ('AIRS','BUSC','CABE','CAMP', 'MOTO','SEMI','TRAI','VANC','CMTP','CTHR','DMOT','FTHR','HTLQ','AMOT','CMOT','TTCO','FWTT','PCTT','BMOT','TOTR') then 'RV'
					else dp.Product
			end)
		and apld.state_apld = 
			(case
					when dp.GoverningState='NC' and (dp.NCRatingTier in ('Preferred','UltraPreferred') or dp.CustomerGroup='PRF') then 'NCPF'
					when dp.GoverningState='NC' then 'NCNS'
					else dp.GoverningState
			end)

where 
	dp.SourceSystemCode not in ('NPS')  /* THIS IS IMPORTANT!!!!!!!!!!!!!!!!!!!!!!!!!!!             */

group by
	fl_cap.PolicyKey
	,fl_cap.RiskKey
	,fl_cap.CoverageKey
	,fl_cap.DOLMonthTimeKey
	,fl_cap.cededCoverageInd

	,cast( dp.planCode as varchar(5) ) 
	,cast( lkpFirm.Grp1 as varchar(6) ) 
	,cast( lkpChannel.Grp1 as varchar(1) ) 
	,cast( case when lkpProdVer.Grp1 is null then 'XX' else lkpProdVer.Grp1 end as varchar(2) ) 
	,cast( case when lkpLOB.Grp1 is null then dp.Product else lkpLOB.Grp1 end as varchar(7) ) 
	,cast( apld.cov_APLD as varchar(10) ) 
	,cast( apld.LDFcov_APLD as varchar(10) ) 
  	,cast( case 
		when dp.Product='PPA' and dp.GoverningState='NC' and (dp.NCRatingTier in ('Preferred','UltraPreferred') or dp.CustomerGroup='PRF') then 'NCPF'
		when dp.Product='PPA' and dp.GoverningState='NC' then 'NCNS'
		else dp.GoverningState
	end as varchar(6) ) 
Option (MaxDOP 0)
/* LOSS NON-NPS ACC PERIOD *************************************************************************************************************************************************************************/


--select 
--	sum(IL_Acc_Cap), 
--	sum(NetFeature) ,
--	sum(NetFeature_Curr_APLD )
--from work.STAGE_FactLossAccNonNPSSys 




/* Combine NPS & Non-NPS Curr Acc Period Losses *************************************************************************************************************************************************************************/
drop table if exists Product_Work.work.STAGE_FactLossAcc_Curr_wNonNPS
select * into work.STAGE_FactLossAcc_Curr_wNonNPS
from
		(SELECT * FROM [Product_Work].work.[STAGE_FactLossAcc_Curr]
		union
		SELECT * FROM [Product_Work].work.[STAGE_FactLossAccNonNPSSys]) tbl
Option (MaxDOP 0)
/* Combine NPS & Non-NPS Curr Acc Period Losses *************************************************************************************************************************************************************************/



--select DoLMonthTimeKey, format(sum(IL_Acc_Cap),'C0'), format(sum(NetFeature),'N0')
--	--format(sum(IL_xLL_Acc_Cap),'C0'), format(sum(IL_cap50kLL_Acc_Cap),'C0') , format(sum(IL_cap100kLL_Acc_Cap),'C0') ,
--	--format(sum(IL_xLL_Acc_Cap2),'C0'), format(sum(IL_cap50kLL_Acc_Cap2),'C0') , format(sum(IL_cap100kLL_Acc_Cap2),'C0') 
--from work.STAGE_FactLossAcc_Curr_wNonNPS as a
--	inner join AnalyticsDataHub.dbo.DimPolicy as dp with (nolock)
--			on a.PolicyKey = dp.PolicyKey 
--			and dp.SourceSystemCode='NPS'
--			and a.cededCoverageInd=0
--where 
--a.LOB_APLD in ('PPA','CV','MC','RV','FV') 
--	and cov_APLD <> 'Excluded'
--group by DoLMonthTimeKey
--order by DoLMonthTimeKey desc







/* LOSS FISCAL *************************************************************************************************************************************************************************/
/* Run monthly w fiscal month-end */
drop table if exists Product_Work.work.STAGE_FactLossFiscal
select
	fl_cap.PolicyKey
	,fl_cap.RiskKey
	,fl_cap.CoverageKey
	,fl_cap.RefCalPerMonthKeyId
	,fl_cap.cededCoverageInd

	,cast( dp.planCode as varchar(5) ) as planCode
	,cast( lkpFirm.Grp1 as varchar(6) ) as firm_APLD
	,cast( lkpChannel.Grp1 as varchar(1) ) as distChannel_APLD
	,cast( case when lkpProdVer.Grp1 is null then 'XX' else lkpProdVer.Grp1 end as varchar(2) ) as prodVer_APLD
	,cast( case when lkpLOB.Grp1 is null then dp.Product else lkpLOB.Grp1 end as varchar(7) ) as LOB_APLD
	,cast( apld.cov_APLD as varchar(10) ) as cov_APLD
	,cast( apld.LDFcov_APLD as varchar(10) ) as LDFcov_APLD
  	,cast( case 
		when dp.Product='PPA' and dp.GoverningState='NC' and (dp.NCRatingTier in ('Preferred','UltraPreferred') or dp.CustomerGroup='PRF') then 'NCPF'
		when dp.Product='PPA' and dp.GoverningState='NC' then 'NCNS'
		else dp.GoverningState
	end as varchar(6) ) as State_APLD

	--,cast( SUM(fl_cap.IL) as decimal(18,2) ) as IL_Fiscal
	,cast( SUM(fl_cap.IL_Cap) as decimal(18,2) ) as IL_Fiscal_Cap 
	,cast( SUM(fl_cap.catIL) as decimal(18,2) ) as catIL_Acc_Cap 
	,SUM(fl_cap.NetFeature) as NetFeature 

into Product_Work.work.STAGE_FactLossFiscal

--from Product_Work.dbo.vw_FactLoss_Cap as fl_cap with (nolock)
from Product_Work.work.FactLoss_Cap as fl_cap with (nolock)

	inner join AnalyticsDataHub.dbo.DimPolicy as dp with (nolock)
			on fl_cap.PolicyKey = dp.PolicyKey 
			and dp.firmID not in ('32','34','39')
			and fl_cap.RefCalPerMonthKeyId >= (select min(FiscalYearMonth) from tpu.DimMonth where T60Ind_Fisc=1)
    inner join AnalyticsDataHub.dbo.DimRisk as dr with (nolock)
			on fl_cap.RiskKey = dr.RiskKey
	inner join AnalyticsDataHub.dbo.DimCoverage as dc with (nolock)
			on fl_cap.CoverageKey = dc.CoverageKey
	left join Product_Work.tpu.lkpMaster as lkpFirm on lkpFirm.lkpType = 'APLD_FIRM' and lkpFirm.lkpItem = dp.FirmId
	left join Product_Work.tpu.lkpMaster as lkpChannel on lkpChannel.lkpType = 'APLD_CHANNEL' and lkpChannel.lkpItem = dp.DistributionChannel
	left join Product_Work.tpu.lkpMaster as lkpProdVer on lkpProdVer.lkpType = 'APLD_PROD_VER' and lkpProdVer.lkpItem = dp.ProductVersion
	left join Product_Work.tpu.lkpMaster as lkpLOB on lkpLOB.lkpType = 'APLD_LOB' and lkpLOB.lkpItem = dr.RiskSubType
	left join Product_Work.tpu.CovMapADHtoAPLD as apld on
		apld.adh_sourceCovCode = 
			(case 
					when dc.SourceCoverageCode='Unknown' and fl_cap.EPICcoverageCode='NA' then fl_cap.ClaimCoverageCode
					when dc.SourceCoverageCode='Unknown' and fl_cap.EPICcoverageCode<>'NA' then fl_cap.EPICcoverageCode
					else dc.SourceCoverageCode 
			end) 
		and apld.lob_apld = 
			(case 
					when dr.RiskSubType in ('BOOM','DUMP','FBTK','HOPP','FTPU','MITK','ROV','SPDE','SBTK','STVN','STRT','TNTK','FTTR','EUTR','OUTR','HTFR','DBUR','FBUR','BUTR','LBUR','LSTR','GNTR','BCTR','DFTR','DBTR','FBTR','LVTR','LBTR','POTR','RTTR','TNTR','TLTR')  then 'FV'
					when dr.RiskSubType in ('AIRS','BUSC','CABE','CAMP', 'MOTO','SEMI','TRAI','VANC','CMTP','CTHR','DMOT','FTHR','HTLQ','AMOT','CMOT','TTCO','FWTT','PCTT','BMOT','TOTR') then 'RV'
					else dp.Product
			end)
		and apld.state_apld = 
			(case
					when dp.GoverningState='NC' and (dp.NCRatingTier in ('Preferred','UltraPreferred') or dp.CustomerGroup='PRF') then 'NCPF'
					when dp.GoverningState='NC' then 'NCNS'
					else dp.GoverningState
			end)

group by
	fl_cap.PolicyKey
	,fl_cap.RiskKey
	,fl_cap.CoverageKey
	,fl_cap.RefCalPerMonthKeyId
	,fl_cap.cededCoverageInd

	,cast( dp.planCode as varchar(5) ) 
	,cast( lkpFirm.Grp1 as varchar(6) ) 
	,cast( lkpChannel.Grp1 as varchar(1) ) 
	,cast( case when lkpProdVer.Grp1 is null then 'XX' else lkpProdVer.Grp1 end as varchar(2) ) 
	,cast( case when lkpLOB.Grp1 is null then dp.Product else lkpLOB.Grp1 end as varchar(7) ) 
	,cast( apld.cov_APLD as varchar(10) ) 
	,cast( apld.LDFcov_APLD as varchar(10) ) 
  	,cast( case 
		when dp.Product='PPA' and dp.GoverningState='NC' and (dp.NCRatingTier in ('Preferred','UltraPreferred') or dp.CustomerGroup='PRF') then 'NCPF'
		when dp.Product='PPA' and dp.GoverningState='NC' then 'NCNS'
		else dp.GoverningState
	end as varchar(6) ) 
Option (MaxDOP 0)
/* LOSS FISCAL *************************************************************************************************************************************************************************/





select RefCalPerMonthKeyId, format(sum(IL_Fiscal_Cap),'N0') as il from work.STAGE_FactLossFiscal group by RefCalPerMonthKeyId order by RefCalPerMonthKeyId desc




/* PREMIUMS *************************************************************************************************************************************************************************/
/* Run monthly w fiscal month-end */
drop table if exists Product_Work.work.STAGE_FactPrem
select
	fp.PolicyKey
	,fp.RiskKey
	,fp.CoverageKey
	,fp.YearMonthKey
	,fp.CededCoverageInd
	--,cast(dc.sourceCoverageCode as varchar(50)) as sourceCoverageCode

  	,cast( case 
			when dp.Product='PPA' and dp.GoverningState='NC' and (dp.NCRatingTier in ('Preferred','UltraPreferred') or dp.CustomerGroup='PRF') then 'NCPF'
			when dp.Product='PPA' and dp.GoverningState='NC' then 'NCNS'
			else dp.GoverningState
	end as varchar(6) ) as State_APLD
	,cast( dp.planCode as varchar(5) ) as planCode
	,cast( lkpFirm.Grp1 as varchar(6) ) as firm_APLD
	,cast( lkpChannel.Grp1 as varchar(1) ) as distChannel_APLD
	,cast( case when lkpProdVer.Grp1 is null then 'XX' else lkpProdVer.Grp1 end as varchar(2) ) as prodVer_APLD
	,cast( case when lkpLOB.Grp1 is null then dp.Product else lkpLOB.Grp1 end as varchar(7) ) as LOB_APLD
	,cast( apld.cov_APLD as varchar(10) ) as cov_APLD
	,cast( apld.LDFcov_APLD as varchar(10) ) as LDFcov_APLD

  ,cast(SUM(fp.WrittenPremiumAmount) as decimal(18,2)) as WP
  ,cast(SUM(fp.EarnedPremiumAmount) as decimal(18,2)) as EP

  ,cast(SUM(fp.WrittenExposure) as decimal(18,4)) as WCY
  ,cast(sum(case 
				when fp.SourceCoverageCode in 
					('BISSL','BI','PD','PIP','PIPOther','EAC','PIPMEDICAL',
					 'CSL','CSLSSL','TOW','MED','PPI','ADD','AD2',
					 'UM','UMUIMBI','UMUIMPD','UMP','UMP','UMCSL','UMBINon','UMBIST','UMBA','UMPA','UMUIMCSL','UMBR','UMPR','UMCSLNS','UMCSLST',
					 'COLL','CLWD','BCOLL','LCOLL','COMP','FTC',
					 'GL','TOOLS', 'AD','ACCFORG','PEST','ROOF') then fp.WrittenExposure
				when dp.GoverningState not in ('AZ', 'SC') and fp.SourceCoverageCode in ('UIMCSL') then fp.WrittenExposure
				when dp.GoverningState = 'WA' and  fp.SourceCoverageCode in ('UIM','UIMP') then fp.WrittenExposure
				else 0
	end) as decimal(18,4)) as WCY_APLD

  ,cast(SUM(fp.EarnedExposure) as decimal(18,4)) as ECY
  ,cast(sum(case 
				when fp.SourceCoverageCode in 
					('BISSL','BI','PD','PIP','PIPOther','EAC','PIPMEDICAL',
					 'CSL','CSLSSL','TOW','MED','PPI','ADD','AD2',
					 'UM','UMUIMBI','UMUIMPD','UMP','UMP','UMCSL','UMBINon','UMBIST','UMBA','UMPA','UMUIMCSL','UMBR','UMPR','UMCSLNS','UMCSLST',
					 'COLL','CLWD','BCOLL','LCOLL','COMP','FTC',
					 'GL','TOOLS','AD','ACCFORG','PEST','ROOF') then fp.EarnedExposure
				when dp.GoverningState not in ('AZ', 'SC') and fp.SourceCoverageCode in ('UIMCSL') then fp.EarnedExposure
				when dp.GoverningState = 'WA' and  fp.SourceCoverageCode in ('UIM','UIMP') then fp.EarnedExposure
				else 0
	end) as decimal(18,4)) as ECY_APLD

into Product_Work.work.STAGE_FactPrem

--from AnalyticsDataHub.dbo.FactPremium as fp with (nolock)
from work.fplu_factprem as fp

	inner join AnalyticsDataHub.dbo.DimPolicy as dp with (nolock)
			on fp.PolicyKey = dp.PolicyKey 
			--and dp.GoverningState in ('VA') 
			--and dp.product = 'PPA' 
			--and dp.CompanySegment = 'Traditional'
	--inner join AnalyticsDataHub.dbo.DimCoverage as dc with (nolock)
	--		on fp.CoverageKey = dc.CoverageKey
    inner join AnalyticsDataHub.dbo.DimRisk as dr with (nolock)
			on fp.RiskKey = dr.RiskKey
	left join Product_Work.tpu.lkpMaster as lkpFirm on lkpFirm.lkpType = 'APLD_FIRM' and lkpFirm.lkpItem = dp.FirmId
	left join Product_Work.tpu.lkpMaster as lkpChannel on lkpChannel.lkpType = 'APLD_CHANNEL' and lkpChannel.lkpItem = dp.DistributionChannel
	left join Product_Work.tpu.lkpMaster as lkpProdVer on lkpProdVer.lkpType = 'APLD_PROD_VER' and lkpProdVer.lkpItem = dp.ProductVersion
	left join Product_Work.tpu.lkpMaster as lkpLOB on lkpLOB.lkpType = 'APLD_LOB' and lkpLOB.lkpItem = dr.RiskSubType
	left join Product_Work.tpu.CovMapADHtoAPLD as apld on
			apld.adh_sourceCovCode = fp.SourceCoverageCode
			and apld.lob_apld = 
				(case 
					when dr.RiskSubType in ('BOOM','DUMP','FBTK','HOPP','FTPU','MITK','ROV','SPDE','SBTK','STVN','STRT','TNTK','FTTR','EUTR','OUTR','HTFR','DBUR','FBUR','BUTR','LBUR','LSTR','GNTR','BCTR','DFTR','DBTR','FBTR','LVTR','LBTR','POTR','RTTR','TNTR','TLTR')  then 'FV'
					when dr.RiskSubType in ('AIRS','BUSC','CABE','CAMP', 'MOTO','SEMI','TRAI','VANC','CMTP','CTHR','DMOT','FTHR','HTLQ','AMOT','CMOT','TTCO','FWTT','PCTT','BMOT','TOTR') then 'RV'
					else dp.Product
				end)
			and apld.state_apld = 
				(case
						when dp.GoverningState='NC' and (dp.NCRatingTier in ('Preferred','UltraPreferred') or dp.CustomerGroup='PRF') then 'NCPF'
						when dp.GoverningState='NC' then 'NCNS'
						else dp.GoverningState
				end)

where dp.CompanySegment='Specialty Vehicle' 
and fp.YearMonthKey >= (select min(FiscalYearMonth) from work.STAGE_DimMonth where T60Ind_Fisc=1)

group by
	fp.PolicyKey
	,fp.RiskKey
	,fp.CoverageKey
	,fp.YearMonthKey
	,fp.CededCoverageInd
	--,cast(dc.sourceCoverageCode as varchar(50)) 

  ,cast( case 
			when dp.Product='PPA' and dp.GoverningState='NC' and (dp.NCRatingTier in ('Preferred','UltraPreferred') or dp.CustomerGroup='PRF') then 'NCPF'
			when dp.Product='PPA' and dp.GoverningState='NC' then 'NCNS'
			else dp.GoverningState
	end as varchar(6) ) 
	,cast( dp.planCode as varchar(5) ) 
	,cast( lkpFirm.Grp1 as varchar(6) ) 
	,cast( lkpChannel.Grp1 as varchar(1) ) 
	,cast( case when lkpProdVer.Grp1 is null then 'XX' else lkpProdVer.Grp1 end as varchar(2) ) 
	,cast( case when lkpLOB.Grp1 is null then dp.Product else lkpLOB.Grp1 end as varchar(7) ) 
	,cast( apld.cov_APLD as varchar(10) ) 
	,cast( apld.LDFcov_APLD as varchar(10) ) 

Option (MaxDOP 0)
/* PREMIUMS *************************************************************************************************************************************************************************/




--select distinct YearMonthKey from Product_Work.work.STAGE_FactPrem order by YearMonthKey
--where  policykey = 507428705





--select dc.SourceCoverageCode, sum(WP) WP
--from work.STAGE_FactPrem as fp
--	left join analyticsDataHub.dbo.DimCoverage as dc
--			on fp.coverageKey = dc.coverageKey
--where dc.SourceCoverageCode in ('Roof','Pest')
--group by dc.SourceCoverageCode




--select cov_APLD, sum(WP) as wp, sum(ecy) as ecy, sum(ECY_APLD) as ECY_APLD 
--from work.STAGE_FactPrem
--where state_APLD = 'NY' and LOB_APLD = 'PPA'
--and YearMonthKey between 202001 and 202012
--group by cov_APLD
--option (maxdop 0)

--/* WA is 250, NY is 246 ECY_APLD */
--select sum(WP) as wp, sum(ecy) as ecy, sum(ECY_APLD) as ECY_APLD
--from work.STAGE_FactPrem
--where state_APLD = 'WA' and LOB_APLD = 'PPA'
--and YearMonthKey between 202001 and 202012
--option (maxdop 0)


--select YearMonthKey, sum(WP) as wp, sum(ecy) as ecy, sum(ECY_APLD) as ECY_APLD 
--from work.STAGE_FactPrem 
----where state_APLD = 'NY' and LOB_APLD in ('PPA')
--group by YearMonthKey order by YearMonthKey desc


--select cov_APLD, sum(WP) as wp, sum(ecy) as ecy, sum(ECY_APLD) as ECY_APLD 
--from work.STAGE_FactPrem 
--where state_APLD = 'NY' and LOB_APLD in ('PPA')
--group by cov_APLD


--select cov_APLD, sourceCoverageCode, sum(WP) as wp, sum(ecy) as ecy, sum(ECY_APLD) as ECY_APLD 
--from work.STAGE_FactPrem 
--where state_APLD = 'NY' and LOB_APLD in ('PPA')
--group by cov_APLD, sourceCoverageCode
--order by cov_APLD


--exec ccix @table = 'work.STAGE_FactLossAcc_202012'
--exec ccix @table = 'work.STAGE_FactLossAcc_201912'
--exec ccix @table = 'work.STAGE_FactLossAcc_201812'



exec Product_Work.i800088.ccix @table = 'work.STAGE_FactLossAcc_Curr_wNonNPS'

exec Product_Work.i800088.ccix @table = 'work.STAGE_FactLossFiscal'
exec Product_Work.i800088.ccix @table = 'work.STAGE_FactPrem'




/* JOIN PREM & LOSS  *************************************************************************************************************************************************************************/
/* Run when APLD CurrMo chg, or fiscal month-end */
drop table if exists Product_Work.work.STAGE_FactPremLoss
select
 	 coalesce (prems.PolicyKey, loss_acc_1.PolicyKey, loss_acc_202112.PolicyKey, loss_acc_202012.PolicyKey, loss_acc_2.PolicyKey, loss_acc_3.PolicyKey, loss_fiscal.PolicyKey)	as PolicyKey

 	 ,coalesce (prems.RiskKey, loss_acc_1.RiskKey, loss_acc_202112.RiskKey, loss_acc_202012.RiskKey, loss_acc_2.RiskKey, loss_acc_3.RiskKey, loss_fiscal.RiskKey) as RiskKey

 	 ,coalesce (prems.CoverageKey, loss_acc_1.CoverageKey, loss_acc_202112.CoverageKey, loss_acc_202012.CoverageKey, loss_acc_2.CoverageKey, loss_acc_3.CoverageKey, loss_fiscal.CoverageKey) as CoverageKey

 	 ,coalesce (prems.YearMonthKey, loss_acc_1.DoLMonthTimeKey, loss_acc_202012.DoLMonthTimeKey, loss_acc_2.DoLMonthTimeKey, loss_acc_3.DoLMonthTimeKey, loss_fiscal.RefCalPerMonthKeyId) as YearMo

 	 ,coalesce(prems.cededCoverageInd, loss_acc_1.cededCoverageInd, loss_acc_202112.cededCoverageInd, loss_acc_202012.cededCoverageInd, loss_acc_2.cededCoverageInd, loss_acc_3.cededCoverageInd, loss_fiscal.cededCoverageInd) as CededCovInd

 	 ,coalesce (prems.planCode, loss_acc_1.planCode, loss_acc_202112.planCode, loss_acc_202012.planCode, loss_acc_2.planCode, loss_acc_3.planCode, loss_fiscal.planCode) as planCode

 	 ,rtrim( coalesce (prems.firm_APLD, loss_acc_1.firm_APLD, loss_acc_202112.firm_APLD, loss_acc_202012.firm_APLD, loss_acc_2.firm_APLD, loss_acc_3.firm_APLD, loss_fiscal.firm_APLD) ) as firm_APLD

 	 ,coalesce (prems.distChannel_APLD, loss_acc_1.distChannel_APLD, loss_acc_202112.distChannel_APLD, loss_acc_202012.distChannel_APLD, loss_acc_2.distChannel_APLD, loss_acc_3.distChannel_APLD, loss_fiscal.distChannel_APLD) as distChannel_APLD

 	 ,coalesce (prems.prodVer_APLD, loss_acc_1.prodVer_APLD, loss_acc_202112.prodVer_APLD, loss_acc_202012.prodVer_APLD, loss_acc_2.prodVer_APLD, loss_acc_3.prodVer_APLD, loss_fiscal.prodVer_APLD) as prodVer_APLD
	  
	 ,rtrim( coalesce (prems.LOB_APLD, loss_acc_1.LOB_APLD, loss_acc_202112.LOB_APLD, loss_acc_202012.LOB_APLD, loss_acc_2.LOB_APLD, loss_acc_3.LOB_APLD, loss_fiscal.LOB_APLD) )	as LOB_APLD

 	 ,rtrim( coalesce (prems.cov_APLD, loss_acc_1.cov_APLD, loss_acc_202112.cov_APLD, loss_acc_202012.cov_APLD, loss_acc_2.cov_APLD, loss_acc_3.cov_APLD, loss_fiscal.cov_APLD)	) as cov_APLD

 	 ,rtrim( coalesce (prems.LDFcov_apld, loss_acc_1.LDFcov_apld, loss_acc_202112.LDFcov_apld, loss_acc_202012.LDFcov_apld, loss_acc_2.LDFcov_apld, loss_acc_3.LDFcov_apld, loss_fiscal.LDFcov_apld) ) as LDFcov_apld

 	 ,rtrim( coalesce(prems.State_APLD, loss_acc_1.State_APLD, loss_acc_202112.State_APLD, loss_acc_202012.State_APLD, loss_acc_2.State_APLD, loss_acc_3.State_APLD, loss_fiscal.State_APLD) ) as State_APLD
	
	,isnull(prems.WP, 0) as WP
	,isnull(prems.EP, 0) as EP
	,isnull(prems.WCY, 0) as WCY
	,isnull(prems.ECY, 0) as ECY
	,isnull(prems.WCY_APLD, 0) as WCY_APLD
	,isnull(prems.ECY_APLD, 0) as ECY_APLD
	
	--,isnull(loss_acc_1.Sal, 0) as Sal
	--,isnull(loss_acc_1.Sub, 0) as Sub
	--,isnull(loss_acc_1.LCR, 0) as LCR
	--,isnull(loss_acc_1.CurrResAmt, 0) as CurrResAmt
	--,isnull(loss_acc_1.PriorResAmt, 0) as PriorResAmt

	,isnull(loss_acc_1.IL_Acc_Cap, 0) as IL_Acc_Cap_Curr

	,isnull(loss_acc_1.catIL_Acc_Cap, 0) as catIL_Acc_Cap

	,isnull(loss_acc_1.PaidLoss_Cap, 0) as PaidLoss_Cap
	,isnull(loss_acc_1.NetFeature, 0) as NetFeature_Curr
	,isnull(loss_acc_1.NetFeature_Curr_APLD, 0) as NetFeature_Curr_APLD

	,isnull(loss_acc_202112.IL_Acc_Cap, 0) as IL_Acc_Cap_202112
	,isnull(loss_acc_202112.NetFeature_202112, 0) as NetFeature_202112
	,isnull(loss_acc_202112.NetFeature_202112_APLD, 0) as NetFeature_202112_APLD

	,isnull(loss_acc_202012.IL_Acc_Cap, 0) as IL_Acc_Cap_202012
	,isnull(loss_acc_202012.NetFeature_202012, 0) as NetFeature_202012
	,isnull(loss_acc_202012.NetFeature_202012_APLD, 0) as NetFeature_202012_APLD

	,isnull(loss_acc_2.IL_Acc_Cap, 0) as IL_Acc_Cap_201912
	,isnull(loss_acc_3.IL_Acc_Cap, 0) as IL_Acc_Cap_201812
	
	,isnull(loss_fiscal.IL_Fiscal_Cap, 0) as IL_Fiscal_Cap
	,isnull(loss_fiscal.catIL_Acc_Cap, 0) as catIL_Fiscal_Cap

	--,isnull(loss_acc_1.IL_xLL_Acc_Cap, 0) as IL_xLL_Acc_Curr
	--,isnull(loss_acc_1.IL_cap50kLL_Acc_Cap, 0) as IL_cap50kLL_Acc_Curr
	--,isnull(loss_acc_1.IL_cap100kLL_Acc_Cap, 0) as IL_cap100kLL_Acc_Curr

	,isnull(case when loss_acc_1.CededCoverageInd = 1 then 0 else (case when loss_acc_1.IL_Acc_Cap >= 50000 then 0 else loss_acc_1.IL_Acc_Cap end) end, 0) as IL_xLL_Curr
	,isnull(case when loss_acc_1.CededCoverageInd = 1 then 0 else (case when loss_acc_1.IL_Acc_Cap >= 50000 then 50000 else loss_acc_1.IL_Acc_Cap end) end, 0) as IL_cap50kLL_Curr
	,isnull(case when loss_acc_1.CededCoverageInd = 1 then 0 else (case when loss_acc_1.IL_Acc_Cap >= 100000 then 100000 else loss_acc_1.IL_Acc_Cap end) end, 0) as IL_cap100kLL_Curr

into Product_Work.work.STAGE_FactPremLoss

from Product_Work.work.STAGE_FactPrem as prems with (nolock)
	
	full outer join Product_Work.work.STAGE_FactLossAcc_Curr_wNonNPS as loss_acc_1 with (nolock)
			on prems.PolicyKey = loss_acc_1.PolicyKey
			and prems.RiskKey = loss_acc_1.RiskKey
			and prems.CoverageKey = loss_acc_1.CoverageKey
			and prems.YearMonthKey = loss_acc_1.DoLMonthTimeKey
			and prems.cededCoverageInd = loss_acc_1.cededCoverageInd

			and prems.planCode = loss_acc_1.planCode
			and prems.firm_APLD = loss_acc_1.firm_APLD
			and prems.distChannel_APLD = loss_acc_1.distChannel_APLD
			and prems.prodVer_APLD = loss_acc_1.prodVer_APLD
			and prems.LOB_APLD = loss_acc_1.LOB_APLD
			and prems.cov_APLD = loss_acc_1.cov_APLD
			and prems.LDFcov_apld = loss_acc_1.LDFcov_apld
			and prems.State_APLD = loss_acc_1.State_APLD

	full outer join Product_Work.work.STAGE_FactLossAcc_202112 as loss_acc_202112 with (nolock)
			on prems.PolicyKey = loss_acc_202112.PolicyKey
			and prems.RiskKey = loss_acc_202112.RiskKey
			and prems.CoverageKey = loss_acc_202112.CoverageKey
			 and prems.YearMonthKey = loss_acc_202112.DoLMonthTimeKey
			and prems.cededCoverageInd = loss_acc_202112.cededCoverageInd

			and prems.planCode = loss_acc_202112.planCode
			and prems.firm_APLD = loss_acc_202112.firm_APLD
			and prems.distChannel_APLD = loss_acc_202112.distChannel_APLD
			and prems.prodVer_APLD = loss_acc_202112.prodVer_APLD
			and prems.LOB_APLD = loss_acc_202112.LOB_APLD
			and prems.cov_APLD = loss_acc_202112.cov_APLD
			and prems.LDFcov_apld = loss_acc_202112.LDFcov_apld
			and prems.State_APLD = loss_acc_202112.State_APLD

	full outer join Product_Work.work.STAGE_FactLossAcc_202012 as loss_acc_202012 with (nolock)
			on prems.PolicyKey = loss_acc_202012.PolicyKey
			and prems.RiskKey = loss_acc_202012.RiskKey
			and prems.CoverageKey = loss_acc_202012.CoverageKey
			 and prems.YearMonthKey = loss_acc_202012.DoLMonthTimeKey
			and prems.cededCoverageInd = loss_acc_202012.cededCoverageInd

			and prems.planCode = loss_acc_202012.planCode
			and prems.firm_APLD = loss_acc_202012.firm_APLD
			and prems.distChannel_APLD = loss_acc_202012.distChannel_APLD
			and prems.prodVer_APLD = loss_acc_202012.prodVer_APLD
			and prems.LOB_APLD = loss_acc_202012.LOB_APLD
			and prems.cov_APLD = loss_acc_202012.cov_APLD
			and prems.LDFcov_apld = loss_acc_202012.LDFcov_apld
			and prems.State_APLD = loss_acc_202012.State_APLD
	
	full outer join Product_Work.work.STAGE_FactLossAcc_201912 as loss_acc_2 with (nolock)
			on prems.PolicyKey = loss_acc_2.PolicyKey
			and prems.RiskKey = loss_acc_2.RiskKey
			and prems.CoverageKey = loss_acc_2.CoverageKey
			 and prems.YearMonthKey = loss_acc_2.DoLMonthTimeKey
			and prems.cededCoverageInd = loss_acc_2.cededCoverageInd

			and prems.planCode = loss_acc_2.planCode
			and prems.firm_APLD = loss_acc_2.firm_APLD
			and prems.distChannel_APLD = loss_acc_2.distChannel_APLD
			and prems.prodVer_APLD = loss_acc_2.prodVer_APLD
			and prems.LOB_APLD = loss_acc_2.LOB_APLD
			and prems.cov_APLD = loss_acc_2.cov_APLD
			and prems.LDFcov_apld = loss_acc_2.LDFcov_apld
			and prems.State_APLD = loss_acc_2.State_APLD

	full outer join Product_Work.work.STAGE_FactLossAcc_201812 as loss_acc_3 with (nolock)
			on prems.PolicyKey = loss_acc_3.PolicyKey
			and prems.RiskKey = loss_acc_3.RiskKey
			and prems.CoverageKey = loss_acc_3.CoverageKey
			and prems.YearMonthKey = loss_acc_3.DoLMonthTimeKey
			and prems.cededCoverageInd = loss_acc_3.cededCoverageInd

			and prems.planCode = loss_acc_3.planCode
			and prems.firm_APLD = loss_acc_3.firm_APLD
			and prems.distChannel_APLD = loss_acc_3.distChannel_APLD
			and prems.prodVer_APLD = loss_acc_3.prodVer_APLD
			and prems.LOB_APLD = loss_acc_3.LOB_APLD
			and prems.cov_APLD = loss_acc_3.cov_APLD
			and prems.LDFcov_apld = loss_acc_3.LDFcov_apld
			and prems.State_APLD = loss_acc_3.State_APLD

	full outer join Product_Work.work.STAGE_FactLossFiscal as loss_fiscal with (nolock)
			on prems.PolicyKey = loss_fiscal.PolicyKey
			and prems.RiskKey = loss_fiscal.RiskKey
			and prems.CoverageKey = loss_fiscal.CoverageKey
			and prems.YearMonthKey = loss_fiscal.RefCalPerMonthKeyId
			and prems.cededCoverageInd = loss_fiscal.cededCoverageInd

			and prems.planCode = loss_fiscal.planCode
			and prems.firm_APLD = loss_fiscal.firm_APLD
			and prems.distChannel_APLD = loss_fiscal.distChannel_APLD
			and prems.prodVer_APLD = loss_fiscal.prodVer_APLD
			and prems.LOB_APLD = loss_fiscal.LOB_APLD
			and prems.cov_APLD = loss_fiscal.cov_APLD
			and prems.LDFcov_apld = loss_fiscal.LDFcov_apld
			and prems.State_APLD = loss_fiscal.State_APLD
--where prems.State_APLD='NY' and prems.LOB_APLD ='PPA'
Option (MaxDOP 0)


--delete from work.STAGE_FactPremLoss where YearMo < (select min(FiscalYearMonth) from work.STAGE_DimMonth where T60Ind_Fisc=1)


exec Product_Work.i800088.ccix @table = 'work.STAGE_FactPremLoss'
/* JOIN PREM & LOSS  *************************************************************************************************************************************************************************/



--select yearmo, format(sum(IL_Acc_Cap_Curr),'C0'),  format(sum(IL_Acc_Cap_Curr - IL_xLL_Curr),'C0')
-- --format(sum(NetFeature_Curr_APLD),'N0'),
--	--format(sum(IL_xLL_Curr),'C0'), format(sum(IL_cap50kLL_Curr),'C0') , format(sum(IL_cap100kLL_Curr),'C0') 
--from work.STAGE_FactPremLoss as a
--	inner join AnalyticsDataHub.dbo.DimPolicy as dp with (nolock)
--	--inner join tpu.DimPolicy as dp with (nolock)
--			on a.PolicyKey = dp.PolicyKey 
--where 
--			dp.SourceSystemCode='NPS'
--			and a.cededCovInd=0
--			and a.cov_APLD<>'Excluded'
--			and a.LOB_APLD in ('PPA','CV','MC','RV','FV') 
----			--and a.State_APLD = 'NY'
----			--and a.LOB_APLD in ('PPA','RV') 
----			and YearMo >= 201606
--group by yearmo
--order by yearmo desc




--select dc.SourceCoverageCode, sum(WP) WP, sum(IL_Fiscal_Cap)
--from work.STAGE_FactPremLoss as fp
--	left join analyticsDataHub.dbo.DimCoverage as dc
--			on fp.coverageKey = dc.coverageKey
--where dc.SourceCoverageCode in ('Roof','Pest')
--group by dc.SourceCoverageCode




/* This step took 50 mins, but sequence number opens lot of potential when compressed by rowstore */
--drop table if exists work.STAGE_FactPremLoss2
--select *, cast( ROW_NUMBER() over (partition by [YearMo], [PolicyKey] order by [YearMo], [PolicyKey]) as int) as seqnum
--into work.STAGE_FactPremLoss2
--from work.STAGE_FactPremLoss
--order by [YearMo],[PolicyKey], [RiskKey], [CoverageKey]
--Option (MaxDOP 0)


--update work.STAGE_FactPremLoss2
--set wf = 0 
--where seqnum<>1
--option (MaxDOP 0)


--exec ccix @table = 'work.STAGE_FactPremLoss2'


--select 
--		format(sum(wp),'N0') wp
--		,format(sum(IL_Acc_Cap_Curr),'N0') IL_Acc_Cap_Curr
--		,format(sum(wf),'N0') wf
--from work.STAGE_FactPremLoss2
--option (MaxDOP 0)



--select 

--		--substring( convert(varchar, YearMo), 1, 4) as Yr,
--		yearmo
--		,format(sum(WP),'C0') WP
--		,format(sum(EP),'C0') EP
--		,format(sum(ECY),'N0') ECY
--		,format(sum(ECY_APLD),'N0') ECY_APLD

--		,format(sum(IL_Acc_Cap_Curr),'N0') IL_Acc_Cap_Curr
--		,format(sum(NetFeature_Curr),'N0') NetFeature_Curr
--		,format(sum(NetFeature_Curr_APLD),'N0') NetFeature_Curr_APLD

--		,format(sum(IL_Acc_Cap_202012),'N0') IL_Acc_Cap_202012
--		,format(sum(NetFeature_202012),'N0') NetFeature_202012
--		,format(sum(NetFeature_202012_APLD),'N0') NetFeature_202012_APLD

--		,format(sum(IL_Acc_Cap_201912),'N0') as IL_Acc_Cap_201912
--		,format(sum(IL_Acc_Cap_201812),'N0') IL_Acc_Cap_201812

--		,format(sum(IL_Fiscal_Cap),'N0') IL_Fiscal

--		--,format(sum(wf),'N0') wf

--from work.STAGE_FactPremLoss
----where State_APLD='NY' and LOB_APLD = 'PPA' 
----and YearMo between 202001 and 202012
--group by 		
----substring( convert(varchar, YearMo), 1, 4) 
--yearmo
--order by 
----substring( convert(varchar, YearMo), 1, 4) 
--yearmo
--Option (MaxDOP 0)





--select format(sum(WP),'C0') WP, format(sum(EP),'C0') EP 
--from work.STAGE_FactPrem as fp inner join AnalyticsDataHub.dbo.DimPolicy as dp with (nolock)		on fp.policyKey = dp.policyKey
--where 	fp.LOB_APLD in ('PPA','CV','MC','RV','FV') 	and dp.SourceSystemCode = 'NPS' 	and fp.cov_APLD <> 'Excluded'

--select format(sum(WP),'C0') WP, format(sum(EP),'C0') EP, format(sum(IL_Acc_Cap_Curr),'N0') IL_Acc_Cap_Curr 
--from work.STAGE_FactPremLoss as fpl	inner join AnalyticsDataHub.dbo.DimPolicy as dp with (nolock)		on fpl.policyKey = dp.policyKey
--where 	fpl.LOB_APLD in ('PPA','CV','MC','RV','FV') 	and dp.SourceSystemCode = 'NPS' 	and fpl.cov_APLD <> 'Excluded' and fpl.cededCovInd=0


--select format(sum(IL_Acc_Cap),'C0')  
--from work.STAGE_FactLossAcc_Curr_wNonNPS as a inner join AnalyticsDataHub.dbo.DimPolicy as dp with (nolock)		on a.policyKey = dp.policyKey
--where 	a.LOB_APLD in ('PPA','CV','MC','RV','FV') 	and dp.SourceSystemCode = 'NPS' 	and a.cov_APLD <> 'Excluded' and a.cededCoverageInd=0

--select format(sum(IL_Acc_Cap_Curr),'C0') , format(sum(IL_cap100kLL_Acc_Curr),'C0') , format(sum(fpl.IL_cap50kLL_Acc_Curr),'C0')  , format(sum(fpl.IL_xLL_Acc_Curr),'C0')  
--from work.STAGE_FactPremLoss as fpl	inner join AnalyticsDataHub.dbo.DimPolicy as dp with (nolock)		on fpl.policyKey = dp.policyKey
--where 	fpl.LOB_APLD in ('PPA','CV','MC','RV','FV') 	and dp.SourceSystemCode = 'NPS' 	and fpl.cov_APLD <> 'Excluded' and fpl.cededCovInd=0












/* ULT LOSS  *************************************************************************************************************************************************************************/
--select distinct LDFcov_APLD, Cov_APLD,  Firm_APLD, distChannel_APLD, ProdVer_APLD from Product_Work.work.STAGE_FactPremLoss where LOB_APLD='PPA' and yearmo >= 202201
--select distinct LDFcov, Cov, Company, DistChannel, product from Product_Work.work.STAGE_APLD_LDFS_Curr where LOB='PPA' and lossyearmo >= 202201
--select distinct Firm_APLD from Product_Work.work.FactPremLossGrp where State_APLD='LA' and LOB_APLD='PPA'
--select distinct Company from Product_Work.dbo.APLD_LDFS  where State='LA' and LOB='PPA'


/*ACC MONTH  IMPORTANT - USUALLY A MONTH LAGGED FROM FISCAL */
--declare @CurrYearMo as int = 202104
/*ACC MONTH  IMPORTANT - USUALLY A MONTH LAGGED FROM FISCAL */


drop table if exists Product_Work.work.STAGE_FactPremLossUlt
select 	
		PolicyKey, RiskKey, CoverageKey
		,YearMo

		,cast(left(YearMo,4) as int) as Yr
		,CededCovInd
		,LOB_APLD
		,Cov_APLD
		,State_APLD
		,distChannel_APLD
		,planCode
		,cast( isnull(lkpDGPCInd.Grp1,0) as varchar(1) ) as DG_PC_Ind	

		,WP as DWP		
		,EP as DEP		
		,adh.WCY_APLD as DWCY

		,case when CededCovInd=1 then 0 else WP end as WP
		,case when CededCovInd=1 then 0 else EP end as EP

		,case when CededCovInd=1 then 0 else WCY end as WCY
		,case when CededCovInd=1 then 0 else adh.ECY end as ECY
		,case when CededCovInd=1 then 0 else adh.WCY_APLD end as WCY_APLD
		,case when CededCovInd=1 then 0 else adh.ECY_APLD end as ECY_APLD
		,case when CededCovInd=1 or Cov_APLD<>'PD' then 0 else adh.ECY end as PD_ECY
		,case when CededCovInd=1 or Cov_APLD<>'CL' then 0 else adh.ECY end as CL_ECY

		,case when CededCovInd=1 then 0 else catIL_Fiscal_Cap end as catIL_Fiscal

		,case when CededCovInd=1 then 0 else PaidLoss_Cap end as PaidLoss_Curr
		,case when CededCovInd=1 then 0 else IL_Acc_Cap_Curr end as IL_Curr
		,case when CededCovInd=1 then 0 else catIL_Acc_Cap end as catIL_Acc_Curr
		,case when CededCovInd=1 then 0 else NetFeature_Curr end as NetFeature_Curr
		,case when CededCovInd=1 then 0 else NetFeature_Curr_APLD end as NetFeature_Curr_APLD

		--,case when CededCovInd=1 then 0 else IL_Acc_Cap_202112 end as IL_202112
		--,case when CededCovInd=1 then 0 else NetFeature_202112 end as NetFeature_202112
		--,case when CededCovInd=1 then 0 else NetFeature_202112_APLD end as NetFeature_202112_APLD

		,case when CededCovInd=1 then 0 else IL_Acc_Cap_202012 end as IL_202012
		,case when CededCovInd=1 then 0 else NetFeature_202012 end as NetFeature_202012
		,case when CededCovInd=1 then 0 else NetFeature_202012_APLD end as NetFeature_202012_APLD

		,case when CededCovInd=1 then 0 else IL_Acc_Cap_201912 end as IL_201912

		,case when CededCovInd=1 then 0 else IL_Acc_Cap_201812 end as IL_201812

		,case when CededCovInd=1 then 0 else adh.IL_xLL_Curr end as IL_xLL_Curr
		,case when CededCovInd=1 then 0 else adh.IL_cap50kLL_Curr end as IL_cap50kLL_Curr
		,case when CededCovInd=1 then 0 else adh.IL_cap100kLL_Curr end as IL_cap100kLL_Curr

		--,apld_202012.ILfactor
		--,apld_202012.ELR
		--,apld_202012.chain_weight

		,case when apld_curr.chain_weight is null or CededCovInd=1 then 0 
				else cast(adh.IL_Acc_Cap_Curr + (apld_curr.chain_weight * apld_curr.ELR * adh.EP) as decimal(18,4))
		end as UIL_Curr

		,case when apld_curr.chain_weight is null or CededCovInd=1 then 0 
				else cast(adh.IL_xLL_Curr + (adh.EP * apld_curr.ELR * apld_curr.chain_weight) as decimal(18,4))
		 end as UIL_xLL_Curr

		,case when apld_curr.chain_weight is null or CededCovInd=1 then 0 
				else cast(adh.IL_cap50kLL_Curr + (adh.EP * apld_curr.ELR * apld_curr.chain_weight) as decimal(18,4))
		 end as UIL_cap50kLL_Curr

		,case when apld_curr.chain_weight is null or CededCovInd=1 then 0 
				else cast(adh.IL_cap100kLL_Curr  + (adh.EP * apld_curr.ELR * apld_curr.chain_weight) as decimal(18,4))
		 end as UIL_cap100kLL_Curr
		 
		--,case when apld_202112.chain_weight is null or CededCovInd=1 then 0 
		--		else cast(case when (adh.IL_Acc_Cap_202112 > 0) then adh.IL_Acc_Cap_202112 + (apld_202112.chain_weight * apld_202112.ELR * adh.EP) else (adh.EP * apld_202112.ELR) * apld_202112.chain_weight end as decimal(18,4))
		-- end as UIL_202112 

		,case when apld_202012.chain_weight is null or CededCovInd=1 then 0 
				else cast(adh.IL_Acc_Cap_202012 + (apld_202012.chain_weight * apld_202012.ELR * adh.EP) as decimal(18,4))
		 end as UIL_202012

		,case when apld_201912.chain_weight is null or CededCovInd=1 then 0 
				else cast(adh.IL_Acc_Cap_201912 + (apld_201912.chain_weight * apld_201912.ELR * adh.EP) as decimal(18,4))
		 end as UIL_201912

		 ,case when apld_201812.chain_weight is null or CededCovInd=1 then 0 
				else cast(adh.IL_Acc_Cap_201812 + (apld_201812.chain_weight * apld_201812.ELR * adh.EP) as decimal(18,4))
		 end as UIL_201812

		,case when  apld_curr.chain_weight_freq is null or CededCovInd=1 then 0 
				else cast(adh.NetFeature_Curr_APLD + (apld_curr.chain_weight_freq * apld_curr.efreq * adh.ECY_APLD) as decimal(18,4)) 
		 end as UCC_Curr

into Product_Work.work.STAGE_FactPremLossUlt

from Product_Work.work.STAGE_FactPremLoss as adh with (nolock)
	
	left join Product_Work.tpu.lkpMaster as lkpDGPCInd on lkpDGPCInd.lkpType = 'DG_PC_GRP' and lkpDGPCInd.lkpItem = planCode

	left join Product_Work.work.STAGE_APLD_LDFS_Curr as apld_curr with (nolock)
		on adh.YearMo = apld_curr.lossYearMo
		and adh.Cov_APLD = apld_curr.Cov
		and adh.LDFcov_apld = apld_curr.LDFcov
		and adh.LOB_APLD = apld_curr.LOB		
		and adh.State_APLD = apld_curr.State
		and adh.Firm_APLD = apld_curr.Company
		and adh.distChannel_APLD= apld_curr.DistChannel
		and adh.ProdVer_APLD = apld_curr.product
		and adh.PlanCode = apld_curr.assoc_code

	--left join Product_Work.work.STAGE_APLD_LDFS_202112 as apld_202112 with (nolock)
	--	on adh.YearMo = apld_202112.lossYearMo
	--	and adh.Cov_APLD = apld_202112.Cov
	--	and adh.LDFcov_apld = apld_202112.LDFcov
	--	and adh.LOB_APLD = apld_202112.LOB		
	--	and adh.State_APLD = apld_202112.State
	--	and adh.Firm_APLD = apld_202112.Company
	--	and adh.distChannel_APLD= apld_202112.DistChannel
	--	and adh.ProdVer_APLD = apld_202112.product
	--	and adh.PlanCode = apld_202112.assoc_code
	
	left join Product_Work.work.STAGE_APLD_LDFS_202012 as apld_202012 with (nolock)
		on adh.YearMo = apld_202012.lossYearMo
		and adh.Cov_APLD = apld_202012.Cov
		and adh.LDFcov_apld = apld_202012.LDFcov
		and adh.LOB_APLD = apld_202012.LOB		
		and adh.State_APLD = apld_202012.State
		and adh.Firm_APLD = apld_202012.Company
		and adh.distChannel_APLD= apld_202012.DistChannel
		and adh.ProdVer_APLD = apld_202012.product
		and adh.PlanCode = apld_202012.assoc_code
	
	left join Product_Work.work.STAGE_APLD_LDFS_201912 as apld_201912 with (nolock)
		on adh.YearMo = apld_201912.lossYearMo
		and adh.Cov_APLD = apld_201912.Cov
		and adh.LDFcov_apld = apld_201912.LDFcov
		and adh.LOB_APLD = apld_201912.LOB		
		and adh.State_APLD = apld_201912.State
		and adh.Firm_APLD = apld_201912.Company
		and adh.distChannel_APLD= apld_201912.DistChannel
		and adh.ProdVer_APLD = apld_201912.product
		and adh.PlanCode = apld_201912.assoc_code
	
	left join Product_Work.work.STAGE_APLD_LDFS_201812 as apld_201812 with (nolock)
		on adh.YearMo = apld_201812.lossYearMo
		and adh.Cov_APLD = apld_201812.Cov
		and adh.LDFcov_apld = apld_201812.LDFcov
		and adh.LOB_APLD = apld_201812.LOB		
		and adh.State_APLD = apld_201812.State
		and adh.Firm_APLD = apld_201812.Company
		and adh.distChannel_APLD= apld_201812.DistChannel
		and adh.ProdVer_APLD = apld_201812.product
		and adh.PlanCode = apld_201812.assoc_code
where YearMo >= (select min(FiscalYearMonth) from tpu.DimMonth where T60Ind_Fisc=1)
		--and adh.State_APLD='MT' and adh.LOB_APLD in ('PPA')
		--and YearMo = 202207
Option (MaxDOP 0)


exec Product_Work.i800088.ccix @table = 'work.STAGE_FactPremLossUlt'
/* ULT LOSS  *************************************************************************************************************************************************************************/



--select max(lossYearMo) from Product_Work.tpu.APLD_LDFS_Curr
--select COUNT(*) from Product_Work.work.STAGE_APLD_LDFS_Curr




--select format(sum(IL_Curr),'C0'), format(sum(NetFeature_Curr_APLD),'N0'),
--	format(sum(IL_xLL_Acc_Curr),'C0'), format(sum(IL_cap50kLL_Acc_Curr),'C0') , format(sum(IL_cap100kLL_Acc_Curr),'C0') 
--from work.STAGE_FactPremLossUlt as a
--	inner join AnalyticsDataHub.dbo.DimPolicy as dp with (nolock)
--			on a.PolicyKey = dp.PolicyKey 
--			and dp.SourceSystemCode='NPS'
--			and a.cededCovInd=0
--where 
--a.LOB_APLD in ('PPA','CV','MC','RV','FV') 
--	and cov_APLD <> 'Excluded'
--	and YearMo >= 201606


--select YearMo, 
--	format(sum(WP),'C0') WP, format(sum(EP),'C0') EP, 
--	format(sum(IL_Curr),'C0') IL_Curr, format(sum(IL_cap100kLL_Curr),'C0') , 
--	format(sum(fpl.IL_cap50kLL_Curr),'C0')  , format(sum(fpl.IL_xLL_Curr),'C0') ,
--	format(sum(fpl.NetFeature_Curr_APLD),'N0') , format(sum(fpl.UCC_Curr),'N0')  ,
--	format(sum(fpl.UIL_Curr),'C0')  , format(sum(fpl.UIL_xLL_Curr),'C0')  
--from work.STAGE_FactPremLossUlt as fpl	
--inner join AnalyticsDataHub.dbo.DimPolicy as dp with (nolock)		on fpl.policyKey = dp.policyKey
--where
--	LOB_APLD in ('PPA','CV','MC','RV','FV') 
--	and SourceSystemCode = 'NPS' 
--	and cov_APLD <> 'Excluded'
--	 gand CededCovInd=0
----and fpl.distChannel_APLD='A'
--group by YearMo
--order by YearMo desc




--select 
--yearmo,
--format(sum(WP),'C0') WP, format(sum(EP),'C0') EP, format(sum(IL_Fiscal),'N0') IL_Fiscal , format(sum(IL_Curr),'N0') IL_Curr , format(sum(UIL_Curr),'N0') UIL_Curr 
--from work.STAGE_FactPremLossUlt
--group by yearmo
--order by yearmo desc



--select dc.SourceCoverageCode, sum(WP) WP, sum(IL_Fiscal) IL_Fiscal, sum(IL_Curr) IL_Curr
--from tpu.FactPremLossUlt as fp
--	left join analyticsDataHub.dbo.DimCoverage as dc
--			on fp.coverageKey = dc.coverageKey
--where dc.SourceCoverageCode in ('Roof','Pest')
--group by dc.SourceCoverageCode


--select distinct dc.SourceCoverageCode
--from analyticsDataHub.dbo.DimCoverage as dc
















/* TEST query */
select 
	--Cov_APLD,
	yearmo,
		--substring( convert(varchar, YearMo), 1, 4) as Yr,
	format(sum(WP),'C0') WP
	,format(sum(EP),'C0') EP
	,format(sum(ECY),'N0') ECY
	,format(sum(ECY_APLD),'N0') ECY_APLD

	,format(sum(IL_Fiscal),'C0') IL_Fiscal

	,format(sum(IL_Curr),'C0') IL_Curr
	,format(sum(UIL_Curr),'C0') UIL_Curr
	,format(sum(NetFeature_Curr),'N0') NetFeature_Curr
	,format(sum(NetFeature_Curr_APLD),'N0') NetFeature_Curr_APLD
	,format(sum(UCC_Curr),'N0') UCC

	,format(sum(IL_202012),'C0') IL_202012
	,format(sum(UIL_202012),'C0') UIL_202012
	,format(sum(NetFeature_202012),'N0') NetFeature_202012
	,format(sum(NetFeature_202012_APLD),'N0') NetFeature_202012_APLD

	,format(sum(IL_201912),'C0') IL_201912
	,format(sum(UIL_201912),'C0') UIL_201912

	,format(sum(IL_201812),'C0') IL_201812
	,format(sum(UIL_201812),'C0') UIL_201812

	,format(sum(IL_xLL_Curr),'N0') IL_xLL_Curr
	,format(sum(IL_cap50kLL_Curr),'N0') IL_cap50kLL_Curr
	,format(sum(IL_cap100kLL_Curr),'N0') IL_cap100kLL_Curr

from work.STAGE_FactPremLossUlt
--from tpu.FactPremLossUlt as fplu
	--inner join tpu.DimPolicy as dp with (nolock)
	--	on fplu.policyKey = dp.policyKey
--where State_APLD='NY' and LOB_APLD in ( 'PPA' )
	--and YearMo between 202001 and 202012
group by 	
	yearmo
	--substring( convert(varchar, YearMo), 1, 4)
order by 		
	yearmo desc
	--substring( convert(varchar, YearMo), 1, 4)
	----	Cov_APLD
Option (MaxDOP 0)








--select 
--CededCovInd, format(sum(IL_Curr),'C0') 
--,format(sum(WP),'C0') 
--,format(sum(EP),'C0') 
--from work.FactPremLossUlt
--group by CededCovInd
 








--delete fplu
----from work.STAGE_FactPremLossUlt as fplu
--from tpu.FactPremLossUlt as fplu
--	--left join work.STAGE_DimPolicy as dp with (nolock)
--	left join tpu.DimPolicy as dp with (nolock)
--		on fplu.policyKey = dp.policyKey
--where dp.firmID in ('32','34','39')



--delete fplu
--from work.STAGE_FactPremLossUlt as fplu
--from tpu.FactPremLossUlt as fplu
--where YearMo < 201604


--select dp.firmID, dp.firm_APLD,  sum(dwp) dwp, sum(wp) wp, sum(IL_Curr) IL_Curr, sum(UIL_Curr) UIL_Curr
--from work.STAGE_FactPremLossUlt as fplu
--	left join work.DimPolicy as dp with (nolock)
--		on fplu.policyKey = dp.policyKey
--group by dp.firmID, dp.firm_APLD
--order by dwp desc




--select dp.sourceSystemCode, sum(dwp) dwp, sum(wp) wp, sum(IL_Curr) IL_Curr, sum(UIL_Curr) UIL_Curr
----from work.FactPremLossUlt as fplu
--from work.STAGE_FactPremLossUlt as fplu
--	left join work.DimPolicy as dp with (nolock)
--		on fplu.policyKey = dp.policyKey
--group by dp.sourceSystemCode
--order by dwp desc





--select distinct lossyearmo from Product_Work.tpu.APLD_LDFS_Curr as apld_curr with (nolock)
--order by lossyearmo desc


