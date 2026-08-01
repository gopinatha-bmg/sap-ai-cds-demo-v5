@AbapCatalog.sqlViewName: 'ZV_FX_MISSING'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'FX Docs Missing Exchange Rate'
@VDM.viewType: #CONSUMPTION
define view ZAI_FX_MISS_RT
  with parameters
    @EndUserText.label: 'Posting Date From'
    p_budat_from       : budat,
    @EndUserText.label: 'Posting Date To'
    p_budat_to         : budat,
    @EndUserText.label: 'Company Code'
    p_company_code     : bukrs,
    @EndUserText.label: 'Fiscal Year'
    p_fiscal_year      : gjahr,
    @EndUserText.label: 'Amount Threshold (Doc Currency)'
    p_amount_threshold : netwr_ap
  as select from bkpf as h
    inner join   bseg as i on  i.bukrs = h.bukrs
                           and i.belnr = h.belnr
                           and i.gjahr = h.gjahr
    inner join   t001 as c on  c.bukrs = h.bukrs
    // LFA1 join only used to enrich SupplierName; left outer preserves non-vendor lines
    left outer join lfa1 as v on v.lifnr = i.lifnr
{
  key h.bukrs                              as CompanyCode,
  key h.belnr                              as AccountingDocument,
  key h.gjahr                              as FiscalYear,
  key i.buzei                              as LineItem,
      h.blart                              as DocumentType,
      h.budat                              as PostingDate,
      h.bldat                              as DocumentDate,
      h.xblnr                              as ReferenceDocument,
      h.waers                              as DocumentCurrency,
      c.waers                              as CompanyCodeCurrency,
      h.kursf                              as HeaderExchangeRate,
      i.kursr                              as LineExchangeRate,
      i.koart                              as AccountType,
      i.lifnr                              as Supplier,
      v.name1                              as SupplierName,
      i.wrbtr                              as AmountInDocCurrency,
      i.dmbtr                              as AmountInLocalCurrency,
      h.stblg                              as ReversalDocument,
      h.stjah                              as ReversalFiscalYear,
      cast( 3 as abap.int1 )               as RiskCriticality
}
where h.budat  between :p_budat_from and :p_budat_to
  and h.bukrs  =  :p_company_code
  and h.gjahr  =  :p_fiscal_year
  // Exclude documents that were reversed AND the reversing documents themselves
  and h.stblg  =  ''
  and h.stjah  =  '0000'
  // FX exception: header currency differs from local currency
  and h.waers  <> c.waers
  // TODO: confirm rule with business. BKPF-KURSF holds the header posting FX rate;
  // BSEG-KURSR is a specialized line-level rate (often blank on standard postings).
  // Current logic flags lines where neither header nor line rate is maintained.
  and h.kursf  =  0
  and i.kursr  =  0
  and abs( i.wrbtr ) >= :p_amount_threshold
}