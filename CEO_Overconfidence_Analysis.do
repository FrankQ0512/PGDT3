/*================================================================================
* 文件名: CEO_Overconfidence_Analysis.do
* 作者: 研究团队
* 创建日期: 2024
* 描述: CEO过度自信对公司融资政策影响的实证分析
*       包括董事会独立性的调节作用分析
* 
* 数据文件:
* - Firm.csv: Compustat财务数据
* - CEO.csv: ExecuComp CEO薪酬数据  
* - Board.csv: BoardEx董事会数据
* - Linking.csv: BoardEx链接文件
*
* 主要分析:
* 1. 数据清理和预处理
* 2. 变量构建（CEO过度自信代理变量、董事会独立性等）
* 3. 样本筛选和缩尾处理
* 4. 主回归分析（杠杆率和现金持有作为因变量）
* 5. 稳健性检验
*================================================================================*/

clear all
set more off
set mem 500m
capture log close

/* 设置工作目录 - 请根据实际路径调整 */
cd "/home/runner/work/PGDT3/PGDT3"

/* 开始日志记录 */
log using "CEO_Overconfidence_Analysis.log", replace

/*================================================================================
* 第1部分: 数据导入和初步清理
*================================================================================*/

display "=== 第1步: 导入和清理财务数据 (Firm.csv) ==="

/* 导入Compustat财务数据 */
import delimited "Firm.csv", clear

/* 数据类型转换和基本清理 */
// 转换数值变量
destring gvkey fyear sic at ceq che dlc dltt ppent ni capx csho prcc_f, replace

// 删除关键变量缺失的观测
drop if missing(gvkey) | missing(fyear)
drop if missing(at) | at <= 0  // 总资产必须为正

// 保留关键变量
keep gvkey fyear sic at ceq che dlc dltt ppent ni capx csho prcc_f

// 按公司和年份排序
sort gvkey fyear

/* 构建基础财务变量 */
display "构建基础财务变量..."

// 市值 (Market Value)
gen mv = csho * prcc_f
label var mv "市值"

// 账面价值 (Book Value)
gen bv = ceq
label var bv "账面价值"

// 市账比 (Market-to-Book Ratio)
gen mb = mv / bv if bv > 0
label var mb "市账比"

// 总负债 (Total Debt)
gen debt = dlc + dltt
replace debt = 0 if missing(debt)
label var debt "总负债"

// 杠杆率 (Leverage Ratio) - 主要因变量之一
gen leverage = debt / at
label var leverage "杠杆率 (债务/总资产)"

// 现金持有比率 (Cash Holdings Ratio) - 主要因变量之二  
gen cash_ratio = che / at
label var cash_ratio "现金持有比率 (现金/总资产)"

// 资产收益率 (ROA)
gen roa = ni / at
label var roa "资产收益率"

// 公司规模 (Firm Size)
gen size = ln(at)
label var size "公司规模 (ln总资产)"

// 资本支出比率 (Capital Expenditure Ratio)
gen capex_ratio = capx / at
label var capex_ratio "资本支出比率"

// 有形资产比率 (Tangibility)
gen tangibility = ppent / at
label var tangibility "有形资产比率"

/* 保存财务数据 */
save "firm_data_clean.dta", replace

display "=== 第2步: 导入和清理CEO数据 (CEO.csv) ==="

/* 导入CEO薪酬数据 */
import delimited "CEO.csv", clear

/* 数据清理 */
// 转换数值变量
destring gvkey year opt_unex_exer_est_val opt_unex_exer_num tdc1, replace

// 保留CEO观测（ceoann包含"CEO"的记录）
keep if strpos(ceoann, "CEO") > 0

// 删除关键变量缺失的观测
drop if missing(gvkey) | missing(year)

// 重命名年份变量以便合并
rename year fyear

/* 构建CEO过度自信代理变量 */
display "构建CEO过度自信代理变量..."

// CEO期权持有价值比率 (Option Holdings Ratio)
gen option_ratio = opt_unex_exer_est_val / tdc1 if tdc1 > 0
label var option_ratio "期权持有价值比率"

// CEO期权数量比率 (Option Number Ratio)  
gen option_num_ratio = opt_unex_exer_num / tdc1 if tdc1 > 0
label var option_num_ratio "期权数量比率"

// 高期权持有虚拟变量 (High Option Holdings Dummy)
// 以期权比率中位数为分界点
summarize option_ratio, detail
gen high_option = (option_ratio >= r(p50)) if !missing(option_ratio)
label var high_option "高期权持有虚拟变量"

// CEO总薪酬对数 (Log Total Compensation)
gen ln_tdc = ln(tdc1) if tdc1 > 0
label var ln_tdc "CEO总薪酬对数"

// 过度自信综合指标 (Overconfidence Index)
// 标准化期权比率作为过度自信的主要代理变量
egen option_ratio_std = std(option_ratio)
gen overconfidence = option_ratio_std
label var overconfidence "CEO过度自信指数"

/* 保留相关变量 */
keep gvkey fyear option_ratio option_num_ratio high_option ln_tdc overconfidence tdc1

/* 处理同一公司同一年有多个CEO的情况，保留薪酬最高的 */
bysort gvkey fyear: egen max_tdc = max(tdc1)
keep if tdc1 == max_tdc
bysort gvkey fyear: keep if _n == 1

/* 保存CEO数据 */
save "ceo_data_clean.dta", replace

display "=== 第3步: 导入和清理董事会数据 (Board.csv) ==="

/* 导入董事会数据 */
import delimited "Board.csv", clear

/* 数据清理和变量构建 */
// 生成年份变量（从起始日期提取）
gen year = real(substr(datestartrole, 7, 4)) if length(datestartrole) >= 10
drop if missing(year)

// 按公司分组统计董事会特征
// 独立董事比例 (Board Independence)
gen independent = (ned == "Yes")
bysort companyid year: egen total_directors = count(_n)
bysort companyid year: egen independent_directors = sum(independent)
bysort companyid year: gen board_independence = independent_directors / total_directors

// 董事会规模 (Board Size)
bysort companyid year: gen board_size = total_directors

/* 保留每个公司-年份一条记录 */
bysort companyid year: keep if _n == 1

/* 保留相关变量 */
keep companyid year board_independence board_size

/* 保存董事会数据 */
save "board_data_clean.dta", replace

display "=== 第4步: 导入链接文件并合并数据 ==="

/* 导入链接文件 */
import delimited "Linking.csv", clear

/* 数据清理 */
destring PERMCO GVKEY companyid, replace
drop if missing(GVKEY) | missing(companyid)

/* 保存链接数据 */
save "linking_data.dta", replace

/*================================================================================
* 第2部分: 数据合并
*================================================================================*/

display "=== 数据合并过程 ==="

/* 开始合并：以财务数据为基础 */
use "firm_data_clean.dta", clear

/* 合并CEO数据 */
merge 1:1 gvkey fyear using "ceo_data_clean.dta"
drop if _merge == 2  // 删除只在CEO数据中存在的观测
gen has_ceo_data = (_merge == 3)
drop _merge

/* 通过链接文件合并董事会数据 */
merge m:1 gvkey using "linking_data.dta", keep(master match)
gen has_linking = (_merge == 3)
drop _merge

merge m:1 companyid fyear using "board_data_clean.dta", keep(master match)
gen has_board_data = (_merge == 3)
drop _merge

/*================================================================================
* 第3部分: 样本筛选和数据预处理
*================================================================================*/

display "=== 第5步: 样本筛选 ==="

/* 记录原始样本量 */
count
local original_n = r(N)
display "原始观测数: `original_n'"

/* 样本筛选条件 */
// 1. 必须有CEO数据
keep if has_ceo_data == 1

count
local after_ceo = r(N)
display "有CEO数据的观测数: `after_ceo'"

// 2. 关键财务变量非缺失
drop if missing(leverage) | missing(cash_ratio) | missing(size) | missing(roa)

count
local after_financial = r(N)
display "有完整财务数据的观测数: `after_financial'"

// 3. 年份范围限制 (假设分析2010-2020年)
keep if fyear >= 2010 & fyear <= 2020

count
local after_year = r(N)
display "限制年份后的观测数: `after_year'"

// 4. 排除金融和公用事业公司 (SIC codes 6000-6999, 4900-4999)
drop if (sic >= 6000 & sic <= 6999) | (sic >= 4900 & sic <= 4999)

count
local final_n = r(N)
display "最终样本观测数: `final_n'"

display "=== 第6步: 缩尾处理 ==="

/* 对连续变量进行1%和99%分位数缩尾处理 */
local winsor_vars "leverage cash_ratio mb roa size capex_ratio tangibility option_ratio ln_tdc"

foreach var of local winsor_vars {
    if "`var'" != "" {
        capture {
            summarize `var', detail
            local p1 = r(p1)
            local p99 = r(p99)
            replace `var' = `p1' if `var' < `p1' & !missing(`var')
            replace `var' = `p99' if `var' > `p99' & !missing(`var')
            display "对变量 `var' 进行缩尾处理: [`p1', `p99']"
        }
    }
}

/*================================================================================
* 第4部分: 变量构建和描述性统计
*================================================================================*/

display "=== 第7步: 构建交互项和虚拟变量 ==="

/* 构建年份和行业虚拟变量 */
// 年份固定效应
tab fyear, gen(year_)

// 行业固定效应 (基于SIC代码两位数)
gen industry = int(sic/100)
tab industry, gen(ind_)

/* 构建交互项：CEO过度自信 × 董事会独立性 */
gen overconf_board_indep = overconfidence * board_independence if !missing(board_independence)
label var overconf_board_indep "CEO过度自信×董事会独立性"

/* 构建额外控制变量 */
// 成长性 (Growth)
gen growth = mb
label var growth "成长性 (市账比)"

// 盈利能力 (Profitability)
gen profitability = roa
label var profitability "盈利能力"

display "=== 第8步: 描述性统计 ==="

/* 主要变量描述性统计 */
local desc_vars "leverage cash_ratio overconfidence board_independence size roa mb tangibility"
summarize `desc_vars'

/* 按CEO过度自信分组的描述性统计 */
display "按CEO过度自信水平分组的描述性统计:"
bysort high_option: summarize leverage cash_ratio board_independence size roa

/* 相关系数矩阵 */
display "主要变量相关系数矩阵:"
correlate leverage cash_ratio overconfidence board_independence size roa mb

/*================================================================================
* 第5部分: 主回归分析
*================================================================================*/

display "=== 第9步: 主回归分析 ==="

/* 模型1: CEO过度自信对杠杆率的影响 */
display "模型1: CEO过度自信对杠杆率的影响"

regress leverage overconfidence size roa mb tangibility i.fyear i.industry, vce(cluster gvkey)
estimates store model1_leverage

/* 模型2: 加入董事会独立性控制变量 */
display "模型2: 加入董事会独立性控制变量"

regress leverage overconfidence board_independence size roa mb tangibility i.fyear i.industry if !missing(board_independence), vce(cluster gvkey)
estimates store model2_leverage

/* 模型3: 加入交互项 - 董事会独立性的调节作用 */
display "模型3: 董事会独立性的调节作用"

regress leverage overconfidence board_independence overconf_board_indep size roa mb tangibility i.fyear i.industry if !missing(board_independence), vce(cluster gvkey)
estimates store model3_leverage

/* 模型4-6: CEO过度自信对现金持有的影响 */
display "模型4: CEO过度自信对现金持有的影响"

regress cash_ratio overconfidence size roa mb tangibility i.fyear i.industry, vce(cluster gvkey)
estimates store model4_cash

display "模型5: 加入董事会独立性控制变量"

regress cash_ratio overconfidence board_independence size roa mb tangibility i.fyear i.industry if !missing(board_independence), vce(cluster gvkey)
estimates store model5_cash

display "模型6: 董事会独立性的调节作用"

regress cash_ratio overconfidence board_independence overconf_board_indep size roa mb tangibility i.fyear i.industry if !missing(board_independence), vce(cluster gvkey)
estimates store model6_cash

/* 输出回归结果表格 */
display "=== 杠杆率回归结果 ==="
estimates table model1_leverage model2_leverage model3_leverage, b(%9.4f) se(%9.4f) stats(N r2)

display "=== 现金持有回归结果 ==="
estimates table model4_cash model5_cash model6_cash, b(%9.4f) se(%9.4f) stats(N r2)

/*================================================================================
* 第6部分: 稳健性检验
*================================================================================*/

display "=== 第10步: 稳健性检验 ==="

/* 稳健性检验1: 使用替代的CEO过度自信测量 */
display "稳健性检验1: 使用高期权持有虚拟变量"

regress leverage high_option board_independence size roa mb tangibility i.fyear i.industry if !missing(board_independence), vce(cluster gvkey)
estimates store robust1_leverage

regress cash_ratio high_option board_independence size roa mb tangibility i.fyear i.industry if !missing(board_independence), vce(cluster gvkey)
estimates store robust1_cash

/* 稳健性检验2: 分子样本分析 - 高vs低董事会独立性 */
display "稳健性检验2: 分样本分析"

// 按董事会独立性中位数分组
summarize board_independence if !missing(board_independence), detail
gen high_board_indep = (board_independence >= r(p50)) if !missing(board_independence)

// 高独立性样本
regress leverage overconfidence size roa mb tangibility i.fyear i.industry if high_board_indep == 1, vce(cluster gvkey)
estimates store robust2_leverage_high

// 低独立性样本  
regress leverage overconfidence size roa mb tangibility i.fyear i.industry if high_board_indep == 0, vce(cluster gvkey)
estimates store robust2_leverage_low

/* 稳健性检验3: 固定效应回归 */
display "稳健性检验3: 公司固定效应"

// 需要先设置面板数据格式
encode gvkey, gen(firm_id)
xtset firm_id fyear

xtreg leverage overconfidence board_independence overconf_board_indep size roa mb tangibility i.fyear if !missing(board_independence), fe cluster(firm_id)
estimates store robust3_leverage_fe

xtreg cash_ratio overconfidence board_independence overconf_board_indep size roa mb tangibility i.fyear if !missing(board_independence), fe cluster(firm_id)
estimates store robust3_cash_fe

/* 稳健性检验4: 内生性处理 - 滞后变量 */
display "稳健性检验4: 使用滞后的CEO过度自信变量"

// 生成滞后变量
sort gvkey fyear
by gvkey: gen overconfidence_lag = overconfidence[_n-1]

regress leverage overconfidence_lag board_independence size roa mb tangibility i.fyear i.industry if !missing(board_independence) & !missing(overconfidence_lag), vce(cluster gvkey)
estimates store robust4_leverage

regress cash_ratio overconfidence_lag board_independence size roa mb tangibility i.fyear i.industry if !missing(board_independence) & !missing(overconfidence_lag), vce(cluster gvkey)
estimates store robust4_cash

/* 稳健性检验5: 倾向得分匹配 */
display "稳健性检验5: 倾向得分匹配分析"

// 基于公司特征预测CEO过度自信
probit high_option size roa mb tangibility i.fyear i.industry if !missing(board_independence)
predict pscore if e(sample)

// 生成匹配样本 (简化版本 - 使用卡尺匹配)
gen matched_sample = 0
bysort high_option: egen pscore_median = median(pscore)
replace matched_sample = 1 if abs(pscore - pscore_median) <= 0.1

// 在匹配样本上重新估计
regress leverage high_option board_independence size roa mb tangibility i.fyear if matched_sample == 1 & !missing(board_independence), vce(cluster gvkey)
estimates store robust5_leverage_psm

/*================================================================================
* 第7部分: 结果输出和解释
*================================================================================*/

display "=== 第11步: 结果汇总 ==="

/* 输出所有回归结果 */
estimates table model1_leverage model2_leverage model3_leverage robust1_leverage robust2_leverage_high robust2_leverage_low, b(%9.4f) se(%9.4f) stats(N r2)

estimates table model4_cash model5_cash model6_cash robust1_cash robust4_cash, b(%9.4f) se(%9.4f) stats(N r2)

estimates table robust3_leverage_fe robust3_cash_fe robust5_leverage_psm, b(%9.4f) se(%9.4f) stats(N r2)

/* 主要结果解释 */
display "=== 主要研究发现 ==="
display "1. CEO过度自信对杠杆率的影响"
display "2. CEO过度自信对现金持有的影响"  
display "3. 董事会独立性的调节作用"
display "4. 稳健性检验结果"

/* 保存最终分析数据集 */
save "final_analysis_data.dta", replace

/* 导出主要结果到Excel */
capture {
    estimates table model1_leverage model2_leverage model3_leverage using "leverage_results.rtf", replace b(%9.4f) se(%9.4f) stats(N r2)
    estimates table model4_cash model5_cash model6_cash using "cash_results.rtf", replace b(%9.4f) se(%9.4f) stats(N r2)
}

/*================================================================================
* 第8部分: 额外分析和图表
*================================================================================*/

display "=== 第12步: 生成图表和额外分析 ==="

/* 散点图: CEO过度自信与杠杆率 */
capture {
    twoway (scatter leverage overconfidence) (lfit leverage overconfidence), ///
        title("CEO过度自信与杠杆率关系") ///
        xtitle("CEO过度自信") ytitle("杠杆率") ///
        note("样本包含`final_n'个观测值")
    graph save "overconfidence_leverage.gph", replace
}

/* 散点图: CEO过度自信与现金持有 */
capture {
    twoway (scatter cash_ratio overconfidence) (lfit cash_ratio overconfidence), ///
        title("CEO过度自信与现金持有关系") ///
        xtitle("CEO过度自信") ytitle("现金持有比率") ///
        note("样本包含`final_n'个观测值")
    graph save "overconfidence_cash.gph", replace
}

/* 边际效应分析 */
display "=== 边际效应分析 ==="

// 重新运行带交互项的模型以计算边际效应
regress leverage overconfidence board_independence overconf_board_indep size roa mb tangibility i.fyear i.industry if !missing(board_independence), vce(cluster gvkey)

// 在不同董事会独立性水平下计算CEO过度自信的边际效应
margins, dydx(overconfidence) at(board_independence=(0.2 0.4 0.6 0.8))

/*================================================================================
* 清理和结束
*================================================================================*/

/* 清理临时文件 */
capture {
    erase "firm_data_clean.dta"
    erase "ceo_data_clean.dta" 
    erase "board_data_clean.dta"
    erase "linking_data.dta"
}

/* 显示最终样本统计 */
display "=== 最终样本统计信息 ==="
display "最终样本观测数: `final_n'"
display "有董事会数据的观测数:"
count if !missing(board_independence)

/* 结束日志 */
log close

display "=== 分析完成 ==="
display "主要输出文件:"
display "1. CEO_Overconfidence_Analysis.log - 完整分析日志"
display "2. final_analysis_data.dta - 最终分析数据集"
display "3. leverage_results.rtf - 杠杆率回归结果"
display "4. cash_results.rtf - 现金持有回归结果"
display "5. overconfidence_leverage.gph - CEO过度自信与杠杆率关系图"
display "6. overconfidence_cash.gph - CEO过度自信与现金持有关系图"

/*================================================================================
* 文件结束
*================================================================================*/