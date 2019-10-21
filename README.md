# BiBi Dai Decentralized Loan Product Description
# 币币贷去中心化借贷产品说明

## 1. Brief Introduction of BiBi Dai

BiBi Dai is operated and managed by Bibidai Distributed Network Technology Service Group Ltd., registered in the Seychelles. Based on The Force Protocol open source framework, BiBi Dai builds a global lending network, formulates exclusive programs based on different borrowing needs of all sectors and groups of society, provides appropriate and effective financial services, pays attention to vulnerable groups in less developed countries or regions, and practices human inclusive finance career.

BiBi Dai's decentralized lending service is a lending dApp based on the mainstream public blockchain such as Ethereum and EOS. It supports peer-to-peer pledge lending and fast lending (fund pool mode), and pledge assets are kept by smart contracts. The BiBi Dai business aims to improve the imbalance of financial services across the globe and to achieve global lending and resource sharing.

## 1. 币币贷简介

币币贷由注册在塞舌尔的 *Bibidai Distributed Network Technology Service Group Ltd.* 运营管理。币币贷依托原力协议开源框架，搭建全球借贷网络，根据社会各阶层和群体的不同借贷需求制定专属方案，提供适当、有效的金融服务，关注欠发达国家或地区的弱势群体，践行人类普惠金融事业。

币币贷的去中心化借贷服务，是基于以太坊、EOS等主流公链开发的借贷dApp，支持点对点质押借贷和汇集流动性借贷，质押资产由智能合约保管。币币贷业务旨在改善全球各区域金融服务的不平衡，实现全球借贷资源共享。

## 2. Peer-to-Peer Loan Product

### 2.1 Product Elements and Rules

Table 1 Decentralized peer-to-peer pledge loan product on Ethereum

| <b>Elements</b> | <b>Rules</b> |
| ------ | ------ |
| <b>Lending coins</b> | USDT(ERC-20), DAI, QIAN, etc.
| <b>Pledge coins</b> | ETH, BNB, FOR, BAT, HT, MKR, LRC, etc.
| <b>Pledge rate</b> | 180% (= pledged coins market value / market value of lending coins)
| <b>Make up line</b> | 150% |
| <b>Closed line</b> | 120% |
| <b>Daily interest rate</b> | 0.1‰ to 0.8‰, set by the participants
| <b>Loan period</b> | 7, 14, 30, 60, 90 days, choose by the participants
| <b>Minimum borrowing amount</b> | From 10 USD
| <b>Handling fee</b> | see notes
| <b>Order limited period</b> | If the order is not filled within 5 natural days, the order will be cancelled by the system.

<b>Notes:</b>

The daily handling rate is 0.5‰ (subject to the page prompt), and the two-way fee is charged to the borrowing user and the lending user. The borrower pays the handling fee when repaying the loan, and the lender pays the handling fee when lending. When the pledge rate is down to 120%, the loan contract will be closed, in which 5% of the pledged token will be transferred to the source channel of the borrowing order, 5% will be used as the closing fee, and 110% will be transferred to the lender.

<br>

### 2.2 Shared Order Book

The borrowing user pledges cryptocurrency to the smart contract, sets the borrowing rate and the borrowing period independently, and creates a borrowing order. Each loan order will enter the BiBi Dai Global Shared Order Book, which is open to all BiBi Dai partners, and any lender from any partner can choose any of the loan orders to lend.

<div align = center>

![GitHub](https://raw.githubusercontent.com/theforceprotocolgroup/TheForceProtocolLending/master/Images/SharedOrderBookEN.jpg "Shared Order Book")

Figure 1 shared order book</div>

<br>

## 2. 点对点借贷产品

### 2.1 产品要素和规则

表1 基于以太坊的去中心化点对点借贷产品

| <b>要素</b> | <b>规则</b> |
| ------ | ------ |
| <b>借币币种</b> | USDT(ERC-20)、DAI、QIAN（原力协议稳定币，即将推出） 
| <b>质押币种</b> | ETH、BNB、FOR、WBTC、BAT、HT、MKR、LRC等 
| <b>质押率</b> | 180%（=质押币市值/借币市值）
| <b>补仓线</b> | 150% |
| <b>平仓线</b> | 120% |
| <b>日利率</b> | 万1到万8，借币用户自主设置 
| <b>借款期限</b> | 7、14、30、60、90天，借币用户自主选择 
| <b>最低借款数量</b> | 等值 10 USD 起
| <b>手续费</b> | 见备注
| <b>订单有限期</b> | 若订单在5个自然日内未成交，订单将被系统取消。

<b>备注：</b>

日手续费率万0.5（以页面提示为准），向借币用户和出借用户双向收费。借币者还款时支付手续费，出借者出借时支付手续费。质押率到达120%时将被平仓，其中5%质押币将转给借币订单来源渠道，5%作为币币贷平仓费用，110%转给出借人。

<br>

### 2.2 共享订单簿

借币用户向智能合约质押数字货币，自主设定借款利率和借款期限即可创建借款订单。每笔借款订单都会进入币币贷共享订单薄，该共享订单簿向所有币币贷合作伙伴开放，来自任何合作伙伴的出借用户可以选择其中任意一笔借款订单进行出借。

<div align = center>

![GitHub](https://raw.githubusercontent.com/theforceprotocolgroup/TheForceProtocolLending/Dev/Images/SharedOrderBookCN.jpg "Shared Order Book")

图1 共享订单薄</div>

<br>

## 3. Fast Lending Product

### 3.1 Design Ideas

Peer-to-peer lending allows both lenders and borrowers to freely determine the terms of lending, but it also brings a lot of inconvenience: to participate in peer-to-peer lending, users need to publish and manage loan orders independently. In the case of mortgage lending, both borrowers and lenders need to pay attention to the price changes of collateral at any time. At the same time, a point-to-point loan order often takes a long wait from the release to the final transaction. These shortcomings limit the scale and growth rate of the peer-to-peer lending business.

The traditional banking industry has greatly improved the efficiency of loans by pooling funds. Through the banking industry, the lending business can really promote the growth of the real economy. However, the traditional banking industry's lending business application process is complex, the probability of borrowers being refused by banks is high, and the inconvenience of traditional banking industry provides opportunities for new lending instruments.

By pooling funds from different sources of funds that meet the same borrowing conditions, it is possible to create a pool of funds that focus on specific borrowing conditions and provide rapid funding to demanders. With smart contract technology, people can pool funds for the first time without going through traditional banking: through automated programs (smart contracts) deployed on the mainstream public blockchain systems, fund providers can quickly get capital gains without friction, and borrowers can get fast and convenient loans, this business model has been recognized by the market in Ethereum's Compound Lending Application.

BiBi Dai set up a technical framework for both peer-to-peer lending and fast lending business models at the beginning of the project. In the actual development, we first realized and perfected the peer-to-peer lending protocol. In the process of developing the fast lending function, we refer to the concept of Compound lending application, and simplified our original pool of fund model based on different loan cycles. Each specific lending asset uses only one fast lending model.

Different from the concept of interest rate model and cToken design of the Compound application, we proposed the original fast lending product structure of BiBi Dai.

### 3.2 Funds Collection

Users of BiBi Dai can transfer the stablecoin assets to smart contracts for custody through dApp's “saving for interest” function to obtain interest income, and BiBi Dai's smart contract summarizes the supply of each user. When the remaining assets in the smart contract are sufficient, the user can transfer their stablecoin assets out of the smart contract at any time without waiting for the loan to expire. At the beginning of the launch, BiBi Dai dApp will provide pools of DAI and USDT stablecoin funds. As the system continues to operate, it will be considered to include more types of stablecoin such as USDC and PAX.

### 3.3 Borrowing Assets

BiBi Dai dApp allows users to directly use their ERC-20 assets for loan collateral, quickly and easily obtain stablecoin funds through fast lending function, without paying attention to order’s terms, as the borrowing time is extended, the interest paid is also predictable, all steps are transparent. With the change in the remaining loanable assets in the stablecoin pool, the borrowing rate will be automatically adjusted according to the algorithm.

At the beginning of the BiBi Dai dApp launch, the smart contract accepted ETH, FOR, BNB, HT, MKR, LRC, ZRX, and BAT as collateral. Because different collateral assets differ in terms of liquidity, usage population, etc., the proportion of borrowings that can be obtained for different collaterals will also be different. The specific loan ratio will be adjusted regularly by the community governance with the development of various collaterals.

### 3.4 Risk and Liquidation

When the borrower's repayment exceeds the value of its collateral, the system will require the borrower to make up the position in time. If the borrower fails to complete the replenishment within the specified time, the collateral will be seized by the smart contract and the liquidation process will be started. At this point, the arbitrage is allowed to call the clearing contract, and the frozen asset is replaced by stablecoin according to a certain discount ratio. Any Ethereum address holding enough stablecoin assets can call the clearing contract. The clearing process is built into the contract and does not depend on the support of the external system, so the clearing process will remain efficient and fast.

### 3.5 Interest Rate Model

BiBi Dai dApp adopts an algorithm-controlled interest rate model. Based on the change of supply and demand, the interest rate is automatically adjusted, which effectively affects the total scale of borrowing and the supply of funds.

For the regulation of borrowing funds, BiBi Dai follows the following principle: When the loan amount in the pool of borrowed funds is low, the interest rate of borrowing rises at a low rate to promote the borrower to borrow from the fund pool; when the amount of borrowed funds in the pool are higher, even close to 100%, the loan interest rate rises faster, which drives the interest rate of deposits to increase, so that depositors will deposit more stablecoin into the pool of funds. Through algorithmic adjustment, ensure that the development and growth of the entire pool of loan fund is in a healthy range.

To quantify the amount of funds borrowed, we introduce the parameter x, which represents the proportion of funds borrowed by asset a. The formula is:

<div align = center>

![GitHub](https://raw.githubusercontent.com/theforceprotocolgroup/TheForceProtocolLending/Dev/Images/bibidai.equation.01.EN.png "x equation")

</div>

Let the loan interest rate be y, y and x can be expressed as a piecewise function as follows:

<div align = center>

![GitHub](https://raw.githubusercontent.com/theforceprotocolgroup/TheForceProtocolLending/Dev/Images/interest.rate.equation01.latex.gif "Pool lending interest rate equation")

</div>

Unlike the model of Compound's simple interest rate change mechanism, BiBi Dai dApp divides the interest rate change into three stages. In the first stage, in order to stimulate the initial loan increase, the interest rate growth model approximates the exponential curve, which is also in line with natural growth. In the second stage, by accumulating a certain amount of borrowings, the rate of interest rate growth has entered a stable period, and its graph meets a straight line with a certain slope; in the third stage, due to the large amount of funds borrowed, the interest rate change of borrowing will be accelerated, and the rate of lending will be appropriately controlled, also promote the increase in deposits. The rate of interest rate increase will gradually approach an extreme value, its graph at this stage is close to the revised index curve.

Correspondingly, the saving interest rate SIR formula is:

<div align = center>

**SIRa = borrowing interest rate y of stablecoin a * borrowed portion x of stablecoin a * (1 - adjust factor s)**

</div>

Where 0 ≤ s < 1, generally 0.1.

### 3.6 Interest Rate Calculation

The annualized interest rate of deposits and the annualized interest rate of borrowings will be converted into interest rates per second, using continuous compound interest calculations. Assuming R is the annualized interest rate of the loan, the formula for calculating the interest rate per second is:

<div align = center>

![GitHub](https://raw.githubusercontent.com/theforceprotocolgroup/TheForceProtocolLending/Dev/Images/bibidai.equation.03.gif "per second interest calculation")

</div>

Therefore, the interest rate at time t:

<div align = center>

![GitHub](https://raw.githubusercontent.com/theforceprotocolgroup/TheForceProtocolLending/Dev/Images/bibidai.equation.04.gif "interest rate of t")

</div>

Where Δt is the time interval from the time t-1 to the time t.

Therefore, assuming that the user borrowing amount is BA, the borrowing time is t0, and the repayment time is t1, the principal and interest for repayment will be

<div align = center>

![GitHub](https://raw.githubusercontent.com/theforceprotocolgroup/TheForceProtocolLending/Dev/Images/bibidai.equation.05.gif "total refund")

</div>

The deposit interest rate and interest calculation formula are similar.

<br>

## 3. 集中借贷产品

### 3.1 设计思路

点对点借贷让借贷双方能够自由的确定借贷的条款，但是也带来了很多不便：参与点对点借贷，用户需要自主发布、管理贷款订单；在抵押借贷的情况下，借贷双方需要随时关注抵押物的价格变化；同时，一笔点对点借贷订单从发布到最终成交，往往需要经过漫长的等待。这些不足之处，限制了点对点借贷业务的规模和增速。

银行通过存款业务将资金集中，大大提高了资金利用的效率，通过银行的贷款业务，实体经济得到资金注入并获得增长。然而，传统银行业的借贷业务申请流程复杂，借款人被银行拒绝贷款的概率高，传统银行业借贷的种种不便因素，为新型的借贷工具提供了发展的机会。

通过将不同资金来源但是符合相同借贷条件的资金集中起来，就可以创造出聚焦于特定借贷条件的资金池，向资金需求方快速提供资金。借助智能合约技术，人们能够首次实现不通过传统银行业汇集出资人的资金：通过部署在主流区块链系统上的自动程序（智能合约），出资方可以无摩擦的快速获得资金收益，有资金需求的借款方在提供合适的抵押物之后就可以快速便捷的获得财务支持，此类业务模式已经在以太坊的Compound借贷协议得到了市场认可。

币币贷在项目创立初期就设立了点对点借贷、集中借贷两种业务模式的技术架构。在实际发展中，我们先实现并完善了点对点借贷协议，在开发集中借贷功能的过程中，我们参考了Compound借贷协议的理念，精简了我们原有的基于不同借款周期的资金池模型，对每种特定的借贷资产只采用一种集中借贷模式。

与Compound协议的利率模型、cToken设计等理念不同，我们提出了币币贷原创的集中借贷产品架构。

### 3.2 资金归集

币币贷的用户可以通过dApp的“存币生息”功能，将稳定币资产转给智能合约托管获取利息收入，由币币贷的智能合约汇总每个用户的供给。在智能合约内的剩余资产足够时，用户可以随时将其稳定币资产从智能合约转出，不需要等待贷款到期。在上线初期，币币贷dApp将提供DAI和USDT两种稳定币的资金池，随着系统的持续运行，将考虑纳入QIAN、USDC、PAX等更多种类的稳定币。

### 3.3 借入资产

币币贷dApp支持用户直接将其ERC-20资产用于借贷抵押，快速便捷的通过集中借贷功能获取稳定币资金，无需挑选借贷条款，借款期限等因素，随着借款时间延长，所付出的利息成本也可供预测，保持了透明。随着稳定币资金池内剩余可出借资产的变化，借款利率将根据算法自动调节。

在币币贷dApp上线初期，智能合约接受ETH、FOR、BNB、HT、MKR、LRC、ZRX、BAT为抵押物。由于不同的抵押物资产在流动性、使用人群等方面存在区别，对于不同的抵押品，能够获得的借贷比例也会有所不同，具体借贷比例数值将会随着各抵押物品种的发展，由社区治理进行定期调整。

### 3.4 风险与清算

当借款人的未偿还借款超过其抵押物限定比例时，系统会要求借款人及时补仓，若借款人未在规定时间内完成补仓，则其抵押物将被智能合约扣押，进入清算流程。此时，允许套利者调用清算合约，按照一定的折价比例用稳定币置换扣押资产，任何持有足够稳定币资产的以太坊地址都可以调用清算合约。清算程序内置于合约中，无需依赖外部系统的支持，因此清算过程将保持高效和快捷。

### 3.5 利率模型

币币贷dApp采用一套算法控制的利率模型，基于供求关系的变化，利率自动调节，从而有效的影响借贷总规模、资金供应量等因素。

对于借贷资金的调控，币币贷遵循以下原则：当借贷资金池内的资金借出量较低时，借贷利率上涨的速度较低，以促进借款人从资金池借款；当借贷资金池内的资金借出量较高，甚至接近饱和时，借贷利率上涨的速度较快，带动存款利率增加，以促进存款人向资金池内存入更多稳定币。通过算法调节，确保整个借贷资金池的发展和增长处于健康的范围。

对资金借出量进行量化，我们引入参数x，代表资产a的资金借出比例，其公式为：

<div align = center>

![GitHub](https://raw.githubusercontent.com/theforceprotocolgroup/TheForceProtocolLending/Dev/Images/bibidai.equation.01.png "x equation")

</div>

设借款利率为y，y 和 x 的关系可以用分段函数表示如下：

<div align = center>

![GitHub](https://raw.githubusercontent.com/theforceprotocolgroup/TheForceProtocolLending/Dev/Images/interest.rate.equation01.latex.gif "Pool lending interest rate equation")

</div>

与Compound这样采取简单利率变化机制的模型不同，币币贷dApp将利率的变化分为了三个阶段，在第一阶段，为了刺激初始的借贷量上涨，利率增长模型近似指数曲线，这也符合自然增长规律；在第二阶段，通过积累一定量的借款额，利率的增长速度进入了稳定期，其图形符合一定斜率的直线；在第三阶段，由于借出的资金量已经较多，借贷利率的增加速率会加快，以适当的控制资金借出速度，促进存款量增加，利率增加的速度会逐渐逼近一个极值，这一阶段的利率变化接近于修正指数曲线。

相对应地，存款利率SIR公式为：

<div align = center>

![GitHub](https://raw.githubusercontent.com/theforceprotocolgroup/TheForceProtocolLending/Dev/Images/bibidai.equation.02.png "SIR calculation")

</div>

其中，0 ≤ s < 1，一般可取0.1。

### 3.6 利率计算

存款年化利率和借款年化利率将转换成每秒利率，采用连续复利计算。假定R为借款年化利率，则每秒利率r的计算公式为：

<div align = center>

![GitHub](https://raw.githubusercontent.com/theforceprotocolgroup/TheForceProtocolLending/Dev/Images/bibidai.equation.03.gif "per second interest calculation")

</div>

所以，t时刻的利率：

<div align = center>

![GitHub](https://raw.githubusercontent.com/theforceprotocolgroup/TheForceProtocolLending/Dev/Images/bibidai.equation.04.gif "interest rate of t")

</div>

其中，Δt是指t-1时刻到t时刻的时间间隔。

因此，假定用户借款金额为BA，借款时刻为t0，还款时刻为t1, 则到期应还本息和为

<div align = center>

![GitHub](https://raw.githubusercontent.com/theforceprotocolgroup/TheForceProtocolLending/Dev/Images/bibidai.equation.05.gif "total refund")

</div>

存款利率和利息计算公式类似。

<br>

## 4. General Module

Based on The Force Protocol open source framework, BiBi Dai is the first available DeFi project supported by The Force Protocol. Technical solutions provided by The Force Protocol include:

+ Oracle
+ Governance mechanism
+ Big data and artificial intelligence

### 4.1 Oracle

The system needs to obtain external prices in real time and monitor changes in the pledge rate for timely liquidation and risk control. In the absence of a mature decentralized oracle solution, the system maintains a whitelist of price feeding addresses instead, which are added or removed by community governance voting. Each feeding price includes price information and price validity period, and the system calculates the median value from all valid feed prices as the final price. After having a oracle solution generally recognized by the industry, the system will switch to the corresponding decentralized oracle to ensure that the feed rate mechanism is fair, just, open and transparent.

### 4.2 Governance Mechanism

The governance of BiBi Dai dApp takes the form of a combination of community governance and management team. For the addition of new stablecoin funds pool, update the global interest rate model, update the oracle address, modify the interest adjustment ratio, management team re-election and other major issues, will be fully discussed and voted by the community; the management team composed of BiBi Dai team members is responsible for daily dApp development operation and maintenance work.

### 4.3 Big Data and Artificial Intelligence

BiBi Dai will try to introduce the credit scoring model into the field of cryptocurrency lending to enhance the lending experience. Specifically, BiBi Dai conducts data analysis on integrated on-chain transaction, transaction information, historical lending information and off-chain information, establishes a loan credit scoring machine learning model, evaluates the borrower's credit status and predicts default probability.

<br>

## 4. 通用模块

币币贷依托原力协议开源框架开发，是原力协议支持的首个落地DeFi项目。由原力协议提供的通用技术解决方案包括：

+ 预言机
+ 治理机制
+ 大数据和人工智能

### 4.1 预言机

系统需要实时获取外部价格以监控质押率的变化，以便及时清算，控制风险。在没有成熟的去中心化预言机解决方案时，系统将维护一个喂价地址白名单，该白名单由社区治理投票新增或去除。每个喂价都包含价格信息和价格有效期，系统从所有有效喂价中计算出中位值作为最终价格。在有了行业普遍认可的预言机方案之后，系统将会切换到对应的去中心化预言机，以保证喂价机制的公平、公正、公开、透明。

### 4.2 治理机制

币币贷dApp的治理采取社区治理和管理团队相结合的形式，涉及增加新的稳定币资金池，更新全局利率模型，更新oracle地址，修改利息调整比例，管理团队改选等重大事项时，将经过社区的充分讨论和投票；币币贷团队成员组成的管理团队则负责日常的dApp开发运营维护工作。

### 4.3 大数据和人工智能

币币贷将尝试把信用评分模型引入数字货币借贷领域，以提升借贷体验。具体而言，币币贷将综合链上转账、交易信息、历史借贷信息和链下信息等进行数据分析，建立借贷信用评分机器学习模型，评估借款人的资信情况和预测违约概率。

<br>

## 5. BiBi Dai Global Lending Network

### 5.1 Our Strengths

+ Really available DeFi products
+ Committed to complete decentralization
+ Smart contract custody assets, contract code open source
+ Automatic settlement of interest rates
+ Sharing a global lending network

### 5.2 Cooperation Nodes

BiBi Dai builds a global lending network through cooperative nodes to realize global lending and resource sharing. All partner nodes can enjoy the fee sharing.

- **Platform cooperation nodes**: cryptocurrency wallet, cryptocurrency exchange and other traffic platforms
- **Regional cooperation nodes**: regional financial institutions and individuals (subject to local laws and regulations).

<div align = center>

![GitHub](https://raw.githubusercontent.com/theforceprotocolgroup/TheForceProtocolLending/Dev/Images/GlobalLendingNetworkEN.jpg "Global Lending Network")

Figure 2 Global Lending Network</div>

<br>

### 5.3 Cooperation Mode

BiBi Dai offers a variety of access methods for different partners.

<b> Table 2 BiBi Dai cooperation mode </b>

| Access method | Account mode | Development needs | Target partners |
| ------------- | ------------- | ------------- | ------------- |
| H5 | custody account | no development required | traffic platform |
| dApp | wallet | a small amount of development | wallet platform |
| API | customization | self-driven development | professional loan platform |

<br>

### 5.4 BiBi Dai Lending Public Welfare Fund

In order to practice the human inclusive finance enterprise, BiBi Dai will establish a public welfare loan fund to provide low-interest loan services to users in less developed countries and regions around the world. For regional cooperation nodes in less developed countries and regions, BiBi Dai will allocate more service fees and provide comprehensive technical and financial support.

<br>

## 5. 币币贷全球借贷网络

### 5.1 我们的优势

- 真正落地的DeFi产品
- 致力于完全去中心化
- 智能合约保管资产，合约代码开源
- 息费自动清结算
- 共享全球借贷网络

### 5.2 合作节点

币币贷通过合作节点搭建全球借贷网络，实现全球借贷资源共享。所有合作节点可以享受手续费分润。

- **平台合作节点**：数字货币钱包、数字货币交易所及其他流量平台等；
- **区域合作节点**：区域性金融机构和个人（需符合当地法律法规）。

<div align = center>

![GitHub](https://raw.githubusercontent.com/theforceprotocolgroup/TheForceProtocolLending/Dev/Images/GlobalLendingNetworkCN.jpg "Global Lending Network")

图2 全球借贷网络</div>

<br>

### 5.3 合作模式

币币贷提供多种接入方式，方便各合作方快速接入。

<b>表2 币币贷合作模式</b>

| 接入方式 | 账户模式 | 是否需要开发 | 适合对象 |
| ------------- | ------------- | ------------- | ------------- |
| H5 | 托管账户 | 无需开发 | 流量平台 |
| dApp | 钱包 | 少量开发 | 钱包平台 |
| API | 自定义 | 自主开发 | 专业借贷平台 |

<br>

### 5.4 币币贷借贷公益基金

为践行人类普惠金融事业，币币贷成立借贷公益基金，向全球欠发达国家和地区用户提供低息借款服务。对欠发达国家和地区的区域性合作节点，币币贷将分配更多服务费，并提供全方位的技术和资金支持。

<br>

## 6. BiBi Dai R&D Plan

Developed with principals of practicality and usability, BiBi Dai is committed to building a fully decentralized global lending network. The progress of the development is expected to be as follows:

<b> Table 3 Decentralized lending product development plan </b>

| Time schedule | Content | Details |
| ------------- | ------------- | ------------- |
| Online already | iOS-based centralized lending products | MVP products |
| Online already | EOS-based decentralized lending products | MVP Products |
| October 2019 | Decentralized lending products based on ETH | Forming a lending network which support dApp and H5 models |
| November 2019 | Decentralized lending product based on ETH | Complete fast lending development |
| December 2019 | ETH-based decentralized lending product | User experience optimization, support for API models, and improved decentralized governance architecture |
| End of 2020 | Decentralized lending products based on The Force Protocol public financial blockchain | Support for all major cryptoassets |

<br>

## 6. 币币贷研发路径

币币贷以实用和落地为准绳开发，致力于推动完全去中心化全球借贷网络搭建。预计研发进度如下：

<b>表3 去中心化借贷产品研发计划</b>

| 时间计划 | 内容 | 详情 |
| ------------- | ------------- | ------------- |
| 已上线 | 基于iOS的中心化借贷产品 | MVP验证性产品 |
| 已上线 | 基于EOS的去中心化借贷产品 | MVP验证性产品 |
| 2019年10月 | 基于ETH的去中心化借贷产品 | 形成借贷网络，支持dApp、H5模式 |
| 2019年11月 | 基于ETH的去中心化借贷产品 | 完成集中借贷开发 |
| 2019年12月 | 基于ETH的去中心化借贷产品 | 用户体验优化、支持API模式、完善去中心治理架构 |
| 预计2020年底 | 基于原力协议金融公链的去中心化借贷产品 | 支持所有主流加密资产 |
