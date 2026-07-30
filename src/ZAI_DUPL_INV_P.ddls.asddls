@AbapCatalog.sqlViewName: 'ZV_DUPL_INV_PAY'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Duplicate Vendor Invoice Payments'
@VDM.viewType: #COMPOSITE
define view ZAI_DUPL_INV_P
  with parameters
    @EndUserText.label: 'Posting Date From'
    p_budat_from        : budat,
    @EndUserText.label: 'Posting Date To'
    p_budat_to          : budat,
    @EndUserText.label: 'Company Code'
    p_company_code      : bukrs,
    @EndUserText.label: 'Fiscal Year'
    p_fiscal_year       : gjahr,
    @EndUserText.label: 'Amount Threshold'
    p_amount_threshold  : wertv7
  as select from bkpf as hdr
    inner join      bseg as itm on  hdr.bukrs = itm.bukrs
                                and hdr.belnr = itm.belnr
                                and hdr.gjahr = itm.gjahr
    left outer join lfa1 as vnd on  itm.lifnr = vnd.lifnr
{
  key hdr.bukrs                                as CompanyCode,
  key hdr.belnr                                as AccountingDocument,
  key hdr.gjahr                                as FiscalYear,
  key itm.buzei                                as LineItem,
      hdr.blart                                as DocumentType,
      hdr.bldat                                as DocumentDate,
      hdr.budat                                as PostingDate,
      hdr.xblnr                                as ExternalReference,
      hdr.waers                                as Currency,
      itm.lifnr                                as Vendor,
      vnd.name1                                as VendorName,
      itm.wrbtr                                as GrossAmount,
      itm.shkzg                                as DebitCreditIndicator,
      // Duplicate signal: another vendor line exists with SAME company code,
      // vendor, currency, gross amount, and external reference, on a DIFFERENT
      // accounting document, posted within +/- 90 days of this posting date.
      // TODO (perf): consider layering — a base CDS projecting vendor invoice
      // lines and this exception CDS doing only the self-match on top.
      cast(
        case when exists ( select 1
                             from bseg as dup_itm
                             inner join bkpf as dup_hdr
                                     on  dup_hdr.bukrs = dup_itm.bukrs
                                     and dup_hdr.belnr = dup_itm.belnr
                                     and dup_hdr.gjahr = dup_itm.gjahr
                            where dup_itm.bukrs =  itm.bukrs
                              and dup_itm.lifnr =  itm.lifnr
                              and dup_itm.wrbtr =  itm.wrbtr
                              and dup_itm.waers =  itm.pswsl
                              and dup_itm.koart =  'K'
                              and dup_hdr.xblnr =  hdr.xblnr
                              and dup_hdr.stblg =  ''
                              and ( dup_hdr.belnr <> hdr.belnr
                                 or dup_hdr.gjahr <> hdr.gjahr )
                              and dup_hdr.budat between add_days( hdr.budat, -90 )
                                                   and add_days( hdr.budat,  90 ) )
             then 3   // High: potential duplicate detected
             else 1   // Low: no match in 90-day window
        end as abap.int1
      )                                        as RiskCriticality
}
where hdr.budat  between :p_budat_from and :p_budat_to
  and hdr.bukrs  = :p_company_code
  and hdr.gjahr  = :p_fiscal_year
  and hdr.stblg  = ''                          // exclude reversing documents
  and itm.koart  = 'K'                         // vendor line items only
  and itm.wrbtr >= :p_amount_threshold
  and hdr.xblnr <> ''                          // external ref required to match duplicates