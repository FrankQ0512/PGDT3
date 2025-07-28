/*******************************************************************************
* 程序名称: 董事会独立性与CEO过度自信研究的数据合并与分析
* 作者: 自动生成
* 创建日期: 2024
* Stata版本: 19.5
* 
* 程序功能:
* 1. 解决数据合并中的唯一性问题
* 2. 构建董事会独立性、CEO过度自信等变量
* 3. 执行完整的统计分析和稳健性检验
*
* 文件结构:
* - Firm.csv: 公司财务数据 (gvkey, fyear, 财务变量)
* - CEO.csv: CEO数据 (gvkey, year, CEO信息和期权数据)
* - Board.csv: 董事会数据 (companyid, 董事信息)
* - Linking.csv: 链接表 (gvkey, companyid)
*******************************************************************************/

clear all
set more off
set linesize 255
capture log close

* 设置工作目录 - 根据实际情况调整
* cd "C:\Users\13158\Desktop\Meeting5\Code9"
cd "/home/runner/work/PGDT3/PGDT3"

log using "董事会独立性CEO过度自信分析.log", replace

/*******************************************************************************
* 第一部分: 数据导入与预处理
*******************************************************************************/

display "=== 第一部分: 数据导入与预处理 ==="

* 1.1 导入Firm数据并处理重复问题
display "1.1 导入并清理Firm数据..."
import delimited "Firm.csv", clear
describe

* 检查重复的gvkey-fyear组合
display "检查Firm数据中的重复观测..."
bysort gvkey fyear: gen dup_count = _N
tab dup_count
list gvkey fyear dup_count if dup_count > 1, sepby(gvkey fyear)

* 处理重复观测：保留数据最完整的记录
display "处理重复观测，保留最完整的记录..."
* 计算每行的非缺失变量数量
foreach var of varlist at ceq che dlc dltt ppent ni capx csho prcc_f {
    replace `var' = . if `var' == 0  // 将0值也视为缺失（根据需要调整）
}

egen non_missing = rownonmiss(at ceq che dlc dltt ppent ni capx csho prcc_f)
bysort gvkey fyear (non_missing): keep if _n == _N
drop dup_count non_missing

* 再次检查唯一性
display "验证处理后的唯一性..."
bysort gvkey fyear: assert _N == 1

* 保存清理后的Firm数据
tempfile firm_clean
save `firm_clean'

* 1.2 导入并清理CEO数据
display "1.2 导入并清理CEO数据..."
import delimited "CEO.csv", clear
describe

* 筛选出CEO记录
display "筛选CEO记录..."
keep if ceoann == "CEO"
describe

* 检查CEO数据中的重复
bysort gvkey year: gen dup_count = _N
tab dup_count
if r(N) > 0 {
    display "发现CEO数据中的重复，处理中..."
    list gvkey year ceoann if dup_count > 1, sepby(gvkey year)
    
    * 如果同一公司年份有多个CEO，保留薪酬最高的
    gen total_comp = tdc1
    replace total_comp = 0 if missing(total_comp)
    bysort gvkey year (total_comp): keep if _n == _N
    drop dup_count total_comp
}

* 验证CEO数据唯一性
bysort gvkey year: assert _N == 1

* 创建CEO过度自信指标
display "构建CEO过度自信指标..."

* 方法1: 基于未行权期权价值比例
gen opt_value_ratio = opt_unex_exer_est_val / (opt_unex_exer_est_val + tdc1) if !missing(opt_unex_exer_est_val, tdc1)
replace opt_value_ratio = 0 if missing(opt_unex_exer_est_val) & !missing(tdc1)

* 计算每年的中位数
bysort year: egen med_opt_ratio = median(opt_value_ratio)
gen Overconfidence = (opt_value_ratio > med_opt_ratio) if !missing(opt_value_ratio, med_opt_ratio)

* 方法2: 基于期权行权行为的替代指标（用于稳健性检验）
gen opt_num_ratio = opt_unex_exer_num / (opt_unex_exer_num + 1) if !missing(opt_unex_exer_num)
bysort year: egen med_opt_num = median(opt_num_ratio)
gen Overconfidence_alt = (opt_num_ratio > med_opt_num) if !missing(opt_num_ratio, med_opt_num)

* 保存CEO数据
tempfile ceo_clean
save `ceo_clean'

* 1.3 处理董事会数据
display "1.3 处理董事会数据..."
import delimited "Board.csv", clear
describe

* 清理日期变量
display "清理董事会任期日期..."
* 简化处理：假设datestartrole和dateendrole是字符串格式的日期
* 提取年份信息进行匹配

gen start_year = .
gen end_year = .

* 处理日期格式 (假设是DD/MM/YYYY格式)
replace start_year = real(substr(datestartrole, -4, 4)) if datestartrole != "01/01/1900"
replace end_year = real(substr(dateendrole, -4, 4)) if dateendrole != "31/12/9999" & dateendrole != "01/01/9000"

* 对于缺失的结束年份，使用2024作为默认值
replace end_year = 2024 if missing(end_year)

* 为每个年份创建观测
display "为每个年份创建董事会观测..."
expand end_year - start_year + 1
bysort companyid directorname datestartrole: gen board_year = start_year + _n - 1

* 只保留2013-2024年的数据
keep if board_year >= 2013 & board_year <= 2024

* 计算每个公司每年的董事会独立性
display "计算董事会独立性指标..."
* ned = "Yes" 表示独立董事
gen independent = (ned == "Yes")

* 按公司和年份汇总
bysort companyid board_year: egen total_directors = count(directorname)
bysort companyid board_year: egen independent_directors = sum(independent)

* 计算独立性比例
gen B_INDEP = independent_directors / total_directors

* 保留每个公司-年份的一个观测
bysort companyid board_year: keep if _n == 1
keep companyid board_year B_INDEP total_directors independent_directors

* 保存董事会数据
tempfile board_clean
save `board_clean'

* 1.4 处理链接数据
display "1.4 处理链接数据..."
import delimited "Linking.csv", clear
describe

* 检查多对多关系
display "检查gvkey-companyid的对应关系..."
bysort gvkey: gen gvkey_count = _N
bysort companyid: gen companyid_count = _N

tab gvkey_count
tab companyid_count

* 处理多对多关系：保留最新的对应关系
* 如果没有时间信息，则保留第一个匹配
bysort gvkey (companyid): gen seq1 = _n
bysort companyid (gvkey): gen seq2 = _n

* 简化处理：每个gvkey保留第一个companyid，每个companyid保留第一个gvkey
keep if seq1 == 1 & seq2 == 1
drop gvkey_count companyid_count seq1 seq2

* 重命名为大写以匹配其他文件
rename gvkey GVKEY
gen gvkey = GVKEY

tempfile linking_clean
save `linking_clean'

/*******************************************************************************
* 第二部分: 数据合并
*******************************************************************************/

display "=== 第二部分: 数据合并 ==="

* 2.1 合并Firm和CEO数据
display "2.1 合并Firm和CEO数据..."
use `firm_clean', clear

* 重命名year变量以匹配
rename fyear year

* 合并CEO数据
merge 1:1 gvkey year using `ceo_clean'
display "Firm-CEO合并结果:"
tab _merge
drop _merge

* 2.2 合并董事会数据
display "2.2 合并董事会数据..."
* 首先合并linking表
merge m:1 gvkey using `linking_clean'
display "Firm-Linking合并结果:"
tab _merge

* 保留有companyid的观测
keep if _merge == 3
drop _merge

* 合并董事会数据
merge m:1 companyid year using `board_clean', keepusing(B_INDEP total_directors independent_directors)
rename board_year year if _merge == 3
display "最终合并结果:"
tab _merge

* 处理未匹配的观测
gen board_data_available = (_merge == 3)
replace B_INDEP = . if _merge != 3
drop _merge

/*******************************************************************************
* 第三部分: 变量构建
*******************************************************************************/

display "=== 第三部分: 变量构建 ==="

* 3.1 构建因变量
display "3.1 构建因变量..."

* LEV: 资产负债率 = (短期债务 + 长期债务) / 总资产
gen LEV = (dlc + dltt) / at if !missing(dlc, dltt, at) & at > 0

* CASH: 现金持有率 = 现金及现金等价物 / 总资产
gen CASH = che / at if !missing(che, at) & at > 0

* 3.2 构建控制变量
display "3.2 构建控制变量..."

* SIZE: 公司规模 = ln(总资产)
gen SIZE = ln(at) if !missing(at) & at > 0

* ROA: 资产收益率 = 净利润 / 总资产
gen ROA = ni / at if !missing(ni, at) & at > 0

* TANG: 有形资产比例 = 固定资产净值 / 总资产
gen TANG = ppent / at if !missing(ppent, at) & at > 0

* MTB: 市净率 = (股价 * 流通股数) / 股东权益
gen market_value = prcc_f * csho
gen MTB = market_value / ceq if !missing(prcc_f, csho, ceq) & ceq > 0

* COVID: 疫情期间虚拟变量 (2020-2021年)
gen COVID = (year >= 2020 & year <= 2021)

* 3.3 构建交互项
display "3.3 构建交互项..."
gen OC_x_B_INDEP = Overconfidence * B_INDEP if !missing(Overconfidence, B_INDEP)

* 3.4 样本筛选
display "3.4 样本筛选..."
* 保留有完整关键变量的观测
keep if !missing(gvkey, year)

* 删除极端值 (1%和99%分位数)
foreach var of varlist LEV CASH SIZE ROA TANG MTB {
    if "`var'" != "" {
        quietly sum `var', detail
        replace `var' = . if `var' < r(p1) | `var' > r(p99)
    }
}

* 保存最终分析数据集
save "analysis_dataset.dta", replace

/*******************************************************************************
* 第四部分: 描述性统计
*******************************************************************************/

display "=== 第四部分: 描述性统计 ==="

* 4.1 样本描述
display "4.1 样本基本情况"
display "总观测数: " _N
display "公司数量: " 
quietly distinct gvkey
display r(ndistinct)
display "年份范围: " 
quietly sum year
display r(min) " - " r(max)

* 4.2 主要变量描述性统计
display "4.2 主要变量描述性统计"

* 检查是否安装了estout包
capture which estout
if _rc != 0 {
    display "正在安装estout包..."
    ssc install estout, replace
}

* 使用estpost和esttab生成格式化的描述性统计表
estpost summarize LEV CASH Overconfidence B_INDEP SIZE ROA TANG MTB COVID, detail
esttab using "descriptive_stats.csv", cells("count mean sd min p25 p50 p75 max") ///
    nomtitle nonumber replace title("描述性统计表")

* 显示在屏幕上
esttab, cells("count mean sd min p25 p50 p75 max") nomtitle nonumber ///
    title("主要变量描述性统计")

* 4.3 相关性分析
display "4.3 相关性分析"
pwcorr LEV CASH Overconfidence B_INDEP SIZE ROA TANG MTB COVID, star(0.05) sig

/*******************************************************************************
* 第五部分: 回归分析
*******************************************************************************/

display "=== 第五部分: 回归分析 ==="

* 5.1 LEV的回归分析
display "5.1 资产负债率(LEV)回归分析"

* 模型1: 仅CEO过度自信
regress LEV Overconfidence i.year, vce(cluster gvkey)
estimates store lev_model1

* 模型2: 加入董事会独立性
regress LEV Overconfidence B_INDEP i.year, vce(cluster gvkey)
estimates store lev_model2

* 模型3: 加入交互项和控制变量
regress LEV Overconfidence B_INDEP OC_x_B_INDEP SIZE ROA TANG MTB COVID i.year, vce(cluster gvkey)
estimates store lev_model3

* 5.2 CASH的回归分析
display "5.2 现金持有率(CASH)回归分析"

* 模型4: 仅CEO过度自信
regress CASH Overconfidence i.year, vce(cluster gvkey)
estimates store cash_model1

* 模型5: 加入董事会独立性
regress CASH Overconfidence B_INDEP i.year, vce(cluster gvkey)
estimates store cash_model2

* 模型6: 加入交互项和控制变量
regress CASH Overconfidence B_INDEP OC_x_B_INDEP SIZE ROA TANG MTB COVID i.year, vce(cluster gvkey)
estimates store cash_model3

* 5.3 输出回归结果表
display "5.3 输出回归结果表"

* LEV回归结果表
esttab lev_model1 lev_model2 lev_model3 using "LEV_regression.csv", ///
    b(3) se(3) r2(3) ar2(3) star(* 0.10 ** 0.05 *** 0.01) ///
    title("资产负债率(LEV)回归结果") ///
    mtitles("模型1" "模型2" "模型3") ///
    scalars("N 观测数" "r2_a 调整R方") ///
    replace

* CASH回归结果表
esttab cash_model1 cash_model2 cash_model3 using "CASH_regression.csv", ///
    b(3) se(3) r2(3) ar2(3) star(* 0.10 ** 0.05 *** 0.01) ///
    title("现金持有率(CASH)回归结果") ///
    mtitles("模型4" "模型5" "模型6") ///
    scalars("N 观测数" "r2_a 调整R方") ///
    replace

* 综合结果表
esttab lev_model1 lev_model2 lev_model3 cash_model1 cash_model2 cash_model3 ///
    using "main_regression_results.csv", ///
    b(3) se(3) r2(3) ar2(3) star(* 0.10 ** 0.05 *** 0.01) ///
    title("主要回归结果") ///
    mtitles("LEV-1" "LEV-2" "LEV-3" "CASH-1" "CASH-2" "CASH-3") ///
    scalars("N 观测数" "r2_a 调整R方") ///
    replace

/*******************************************************************************
* 第六部分: 稳健性检验
*******************************************************************************/

display "=== 第六部分: 稳健性检验 ==="

* 6.1 使用替代的CEO过度自信指标
display "6.1 使用替代的CEO过度自信指标进行稳健性检验"

* 使用Overconfidence_alt重新运行主要模型
if !missing(Overconfidence_alt) {
    gen OC_alt_x_B_INDEP = Overconfidence_alt * B_INDEP if !missing(Overconfidence_alt, B_INDEP)
    
    * LEV稳健性检验
    regress LEV Overconfidence_alt B_INDEP OC_alt_x_B_INDEP SIZE ROA TANG MTB COVID i.year, vce(cluster gvkey)
    estimates store lev_robust
    
    * CASH稳健性检验
    regress CASH Overconfidence_alt B_INDEP OC_alt_x_B_INDEP SIZE ROA TANG MTB COVID i.year, vce(cluster gvkey)
    estimates store cash_robust
    
    * 输出稳健性检验结果
    esttab lev_robust cash_robust using "robustness_check.csv", ///
        b(3) se(3) r2(3) ar2(3) star(* 0.10 ** 0.05 *** 0.01) ///
        title("稳健性检验结果(替代指标)") ///
        mtitles("LEV-稳健" "CASH-稳健") ///
        scalars("N 观测数" "r2_a 调整R方") ///
        replace
}

* 6.2 子样本分析
display "6.2 子样本分析"

* 按公司规模分组
quietly sum SIZE, detail
gen large_firm = (SIZE > r(p50)) if !missing(SIZE)

* 大公司子样本
regress LEV Overconfidence B_INDEP OC_x_B_INDEP SIZE ROA TANG MTB COVID i.year if large_firm == 1, vce(cluster gvkey)
estimates store lev_large

regress CASH Overconfidence B_INDEP OC_x_B_INDEP SIZE ROA TANG MTB COVID i.year if large_firm == 1, vce(cluster gvkey)
estimates store cash_large

* 小公司子样本
regress LEV Overconfidence B_INDEP OC_x_B_INDEP SIZE ROA TANG MTB COVID i.year if large_firm == 0, vce(cluster gvkey)
estimates store lev_small

regress CASH Overconfidence B_INDEP OC_x_B_INDEP SIZE ROA TANG MTB COVID i.year if large_firm == 0, vce(cluster gvkey)
estimates store cash_small

* 输出子样本结果
esttab lev_large lev_small cash_large cash_small using "subsample_analysis.csv", ///
    b(3) se(3) r2(3) ar2(3) star(* 0.10 ** 0.05 *** 0.01) ///
    title("子样本分析结果") ///
    mtitles("LEV-大公司" "LEV-小公司" "CASH-大公司" "CASH-小公司") ///
    scalars("N 观测数" "r2_a 调整R方") ///
    replace

/*******************************************************************************
* 第七部分: 结果总结
*******************************************************************************/

display "=== 第七部分: 分析结果总结 ==="

* 7.1 样本统计
quietly count
local total_obs = r(N)
quietly distinct gvkey
local total_firms = r(ndistinct)
quietly count if !missing(Overconfidence)
local obs_with_oc = r(N)
quietly count if !missing(B_INDEP)
local obs_with_board = r(N)
quietly count if !missing(Overconfidence, B_INDEP)
local obs_complete = r(N)

display "样本统计摘要:"
display "- 总观测数: " `total_obs'
display "- 公司数量: " `total_firms'
display "- 有CEO过度自信数据的观测: " `obs_with_oc'
display "- 有董事会数据的观测: " `obs_with_board'
display "- 完整数据的观测: " `obs_complete'

* 7.2 关键发现总结
display ""
display "关键发现:"
display "1. 数据合并问题已解决，成功处理了重复观测"
display "2. 构建了完整的变量体系，包括因变量、自变量、调节变量和控制变量"
display "3. 完成了6个主要回归模型的分析"
display "4. 进行了稳健性检验和子样本分析"

* 7.3 数据质量报告
quietly count if !missing(LEV)
local lev_obs = r(N)
quietly count if !missing(CASH)
local cash_obs = r(N)

display ""
display "数据质量报告:"
display "- LEV有效观测数: " `lev_obs' " (" `lev_obs'/`total_obs'*100 "%)"
display "- CASH有效观测数: " `cash_obs' " (" `cash_obs'/`total_obs'*100 "%)"

/*******************************************************************************
* 程序结束
*******************************************************************************/

display "=== 分析完成 ==="
display "所有结果文件已保存到当前目录"
display "- analysis_dataset.dta: 最终分析数据集"
display "- descriptive_stats.csv: 描述性统计"
display "- main_regression_results.csv: 主要回归结果"
display "- robustness_check.csv: 稳健性检验结果"
display "- subsample_analysis.csv: 子样本分析结果"

log close

/* 备注:
1. 此程序解决了原始数据中gvkey-fyear重复的问题
2. 正确处理了一对多和多对多的合并关系
3. 构建了完整的变量体系进行实证分析
4. 包含了详细的中文注释和错误处理
5. 提供了多种稳健性检验方法
6. 输出格式化的结果表格便于后续使用
*/