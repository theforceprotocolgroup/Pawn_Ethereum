pragma solidity ^0.5.13;

import "./FixidityLib.sol";


contract InterestRateModel {
    using FixidityLib for FixidityLib.Fixidity;

	FixidityLib.Fixidity public fixidity;
    address public admin;
	
    int public constant point1 =       381966011250105152;//0.382*1e18, (3-sqrt(5))/2
    int public constant point2 =       618033988749894848;//0.618*1e18, (sqrt(5)-1)/2
    //https://www.mathsisfun.com/numbers/e-eulers-number.html
    int public constant e =           2718281828459045235;//2.71828182845904523536*1e18
    
    int public constant goldenRatio = 1618033988749894848;//1.618033988749894848

    int public constant sqrt5 =       2236067977499789696;//2.23606797749978969640917366873127623544061835961152572427089
    
    int public constant minInterest =   15000000000000000;//0.015*1e18
    int public constant maxInterest =  200000000000000000;//0.200*1e18
    
    int public reserveRadio =          100000000000000000;//10% spread
    
    int public a;
    int public b;
    int public eDelta;
    int public a1;
    int public a2;
    int public ln1_b;
    int public lnx_b;

    constructor () public {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin can do this!");
        _;
    }
    
    function setAdmin(address newAdmin) public onlyAdmin {
        admin = newAdmin;
    }

	
	function init(uint8 digits) public onlyAdmin {
		fixidity.init(digits);
	}
	
	function setReserveRatio(int radio) public onlyAdmin {
	    reserveRadio = radio;
	}
    
    function sqrt(uint x) public view returns (uint y) {
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
    
    //y=0.015+x^e; x: [0, (3-sqrt(5))/2], [0,0.382]
    function curve1(int x) public view returns (int y) {
        // y = minInterest + x**e;
        int xPowE = fixidity.power_any(x, e);//x**e
        y = fixidity.add(minInterest, xPowE);
    }
    
    //y=0.015+((3-sqrt(5))/2)**(e-1)*x; x:[(3-sqrt(5))/2,(sqrt(5)-1)/2], [0.382,0.618]
    function lineraSegment(int x) public view returns (int y) {
        // require(x > point1 && x <= point2, "invalid x in lineraSegment");
        int k = fixidity.power_any(point1, e-1e18);
        int kx = fixidity.multiply(k, x);
        y = fixidity.add(minInterest,kx);
    }

    // y = ((3-sqrt(5))/2)^(e-1) - (1-x)^e + 0.015
    // y = 0.015 - (1-x)^e+point1^(e-1)
    function curve2(int x) public returns (int y) {
        if (x == 1e18) {
            y = 206337753576934987;//0.206337753576934987*1e18
        } else {
            int c = fixidity.power_any(point1, e-1e18);//point1^(e-1)
            c = fixidity.add(c, minInterest);
            int x2 = fixidity.power_any(fixidity.subtract(1e18, x), e);
            y = fixidity.subtract(c, x2);
        }
    }

    //获取使用率
    function getBorrowPercent(int cash, int borrow) public returns (int y) {
        int total = fixidity.add(cash, borrow);
        if (total == 0) {
            y = 0;
        } else {
            y = fixidity.divide(borrow, total);
        }
    }
    
    //loanRate
    function getLoanRate(int cash, int borrow) public returns (int y) {
        int u = getBorrowPercent(cash, borrow);
        if (u == 0) {
            return 0;
        }
        if (fixidity.subtract(u, point1) < 0) {
            y = curve1(u);
        } else if (fixidity.subtract(u, point2) < 0) {
            y = lineraSegment(u);
        } else {
            y = curve2(u);
        }
    }
    
    //depositRate
    function getDepositRate(int cash, int borrow) public returns (int y) {
        int loanRate = getLoanRate(cash, borrow);
        int loanRatePercent = fixidity.multiply(loanRate, getBorrowPercent(cash, borrow));
        y = fixidity.multiply(loanRatePercent, fixidity.subtract(1e18, reserveRadio));
    }

    //Index(a, n) = Index(a, n-1) * (1 + r*t), Index为本金
    function calculateInterestIndex(int Index, int r, int t) public returns (int y) {
        if (t == 0) {
            y = Index;
        } else {
            int rt = fixidity.multiply(r, t);
            int sum = fixidity.add(rt, fixidity.fixed_1);
            y = fixidity.multiply(Index, sum);//返回本息
        }
    }

    //r为年利率,t为秒数,p*e^(rt)
    function pert(int principal, int r, int t) public returns (int y) {
        if (t == 0) {
            y = principal;
        } else {
            int r1 = fixidity.log_e(fixidity.add(r, fixidity.fixed_1));//r1 = ln(r+1)
            int r2 = fixidity.divide(r1, 60*60*24*365*1e18);//r2=r1/(60*60*24*365)
            int interest = fixidity.power_e(fixidity.multiply(r2, t));//e^(r2*t)
            y = fixidity.multiply(principal, interest);//返回本息
        }
    }

    //r为年利率,t为秒数，计算当前利率（算上本金，2.5%，对应1.025）
    function continuousCompoundingInterest(int r, int t) public returns (int y) {
        if (t == 0) {
            y = r+1;
        } else {
            int r1 = fixidity.log_e(fixidity.add(r, fixidity.fixed_1));//r1 = ln(r+1)
            int r2 = fixidity.divide(r1, 60*60*24*365*1e18);//r2=r1/(60*60*24*365)
            y = fixidity.power_e(fixidity.multiply(r2, t));//e^(r2*t)
        }
    }

    //y=e^(r*t)
    function ert(int r, int t) public returns (int y) {
        if (t == 0) {
            y = 1;
        } else {
            y = fixidity.power_e(fixidity.multiply(r, t));
        }
    }

    function calculateBalance(int principal, int lastIndex, int newIndex) public returns (int y) {
        if (principal == 0 || lastIndex == 0) {
            y = 0;
        } else {
            y = fixidity.divide(fixidity.multiply(principal, newIndex), lastIndex);
        }
    }

    function mul(int a, int b) public returns (int c) {
        c = fixidity.multiply(a, b);
    }

    function mul3(int a, int b, int c) public returns (int d) {
        d = mul(a, mul(b, c));
    }

    function getNewReserve(int oldReserve, int cash, int borrow, int blockDelta) public returns (int y) {
        int borrowRate = getLoanRate(cash, borrow);
        int simpleInterestFactor = fixidity.multiply(borrowRate, blockDelta);
        y = fixidity.add(oldReserve, mul3(simpleInterestFactor, borrow, reserveRadio));
    }
}
