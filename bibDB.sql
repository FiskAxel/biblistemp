DROP DATABASE Bibliotek;
CREATE DATABASE Bibliotek;
USE Bibliotek;

CREATE TABLE Item (
	id INT AUTO_INCREMENT,
    title VARCHAR(75) NOT NULL,
    subtitle VARCHAR(100),
    yearPublished VARCHAR(4),
    mediaType VARCHAR(20) CHECK (mediaType IN ('Bok', 'Film', 'Tidskrift')) NOT NULL,
    language VARCHAR(20) NOT NULL,
    isbn VARCHAR(13) DEFAULT NULL,
    ageLimit VARCHAR(2),
    country VARCHAR(30),
    issn VARCHAR(8) DEFAULT NULL,
    PRIMARY KEY (id)
);
CREATE TABLE Author (
	id INT AUTO_INCREMENT,
    authorName VARCHAR(30) NOT NULL,
    PRIMARY KEY (id)
);
CREATE TABLE ItemAuthor (
	itemID INT,
    authorID INT,
    PRIMARY KEY (itemID, authorID),
    FOREIGN KEY (itemID) REFERENCES Item(id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (authorID) REFERENCES Author(id) ON UPDATE CASCADE ON DELETE NO ACTION
);
CREATE TABLE Classification (
	id INT AUTO_INCREMENT,
    classificationName VARCHAR(30) NOT NULL,
    PRIMARY KEY (id)
);
CREATE TABLE ItemClassification (
	itemID INT,
    classificationID INT,
    PRIMARY KEY (itemID, classificationID),
    FOREIGN KEY (itemID) REFERENCES Item(id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (classificationID) REFERENCES Classification(id) ON UPDATE CASCADE ON DELETE NO ACTION
);
CREATE TABLE Actor (
	id INT AUTO_INCREMENT,
    actorName VARCHAR(30),
    PRIMARY KEY (id)
);
CREATE TABLE ItemActor (
	itemID INT,
    actorID INT,
    PRIMARY KEY (itemID, actorID),
    FOREIGN KEY (itemID) REFERENCES Item(id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (actorID) REFERENCES actor(id) ON UPDATE CASCADE ON DELETE NO ACTION
);

CREATE TABLE Category (
	id INT AUTO_INCREMENT,
    categoryName VARCHAR(30) NOT NULL,
    loanPeriod INT CHECK (loanPeriod IN (0, 7, 14, 30)) NOT NULL,
    PRIMARY KEY (id)
);
CREATE TABLE Copy (
	barcode INT,
    itemID INT NOT NULL,
    location VARCHAR(10) NOT NULL,
    categoryID INT NOT NULL,
    PRIMARY KEY (barcode),
    FOREIGN KEY (itemID) REFERENCES Item(id) ON UPDATE CASCADE ON DELETE NO ACTION,
    FOREIGN KEY (categoryID) REFERENCES Category(id) ON UPDATE CASCADE ON DELETE NO ACTION
);
CREATE TABLE UserType (
	id INT AUTO_INCREMENT,
    userTypeName VARCHAR(10) CHECK (userTypeName IN ('Allmän', 'Student', 'Anställd', 'Forskare', 'admin')) NOT NULL,
    maxNumberOfLoans INT NOT NULL,
    PRIMARY KEY (id)
);
CREATE TABLE User (
	id INT AUTO_INCREMENT,
    userTypeID INT NOT NULL,
    firstName VARCHAR(30) NOT NULL,
    lastName VARCHAR(30) NOT NULL,
    idNumber VARCHAR(12) NOT NULL CHECK (regexp_like(idNumber, '[0-9]') AND length(idNumber) = 12),
    eMail VARCHAR(100) NOT NULL,
    pinCode VARCHAR(4) NOT NULL CHECK (regexp_like(pinCode, '[0-9]') AND length(pinCode) = 4),
    numCurrentLoans INT NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    FOREIGN KEY (userTypeID) REFERENCES UserType(id) ON UPDATE CASCADE ON DELETE NO ACTION
);
CREATE TABLE Loan (
	id INT AUTO_INCREMENT,
    userID INT NOT NULL,
    barcode INT NOT NULL,
    startDate DATETIME NOT NULL DEFAULT now(),
    returnDate DATETIME DEFAULT NULL,
    dueDate DATE NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY (barcode) REFERENCES Copy(barcode) ON UPDATE CASCADE ON DELETE NO ACTION,
    FOREIGN KEY (userID) REFERENCES User(id) ON UPDATE CASCADE ON DELETE NO ACTION
);

CREATE INDEX idx_title ON Item(title);
CREATE INDEX idx_isbn ON Item(isbn);
CREATE INDEX idx_authorName ON Author(authorName);
CREATE INDEX idx_classificationName ON Classification(classificationName);
CREATE INDEX idx_actorName ON Actor(actorName);
CREATE INDEX idx_itemID ON Copy(itemID);


--
-- TRIGGERS, FUNCTIONS, PROCEDURES
--

DELIMITER ##
-- TRIGGERS

CREATE TRIGGER addLoanCount
AFTER INSERT ON loan
FOR EACH ROW
BEGIN
	UPDATE User
	SET numCurrentLoans = (numCurrentLoans + 1)
	WHERE user.id = NEW.userID;
END ##

CREATE TRIGGER decLoanCount
AFTER UPDATE ON loan
FOR EACH ROW
BEGIN
	IF NOT (NEW.returnDate <=> OLD.returnDate)
		THEN UPDATE User
		SET numCurrentLoans = (numCurrentLoans - 1)
        WHERE user.id = NEW.userID;
	END IF;
END ##

CREATE TRIGGER checkLoanCount
BEFORE INSERT ON loan
FOR EACH ROW
BEGIN
	DECLARE currentLoan int;
	DECLARE allowedLoan int;
	SET currentLoan = (SELECT numCurrentLoans FROM user WHERE user.ID = NEW.userID);
	SET allowedLoan = (SELECT maxNumberOfLoans FROM userType Where userType.id = (SELECT userTypeid FROM user WHERE user.id = NEW.userID));
	IF (currentLoan >= allowedLoan)
		THEN SIGNAL SQLSTATE '45000' set message_text = "Du har maximalt antal lån";
	END IF;
END##

CREATE TRIGGER blockRefLoan
BEFORE INSERT ON loan
FOR EACH ROW
BEGIN
	DECLARE currentLoan VARCHAR(30);
	SET currentLoan = (SELECT categoryName FROM category WHERE category.id = (SELECT copy.categoryID FROM copy WHERE copy.barcode = NEW.barcode));
	IF (currentLoan = 'Referens')
		THEN SIGNAL SQLSTATE '45000' set message_text = "Det går inte att låna referensexemplar.";
	END IF;
    IF (currentLoan = 'Tidskrift')
		THEN SIGNAL SQLSTATE '45000' set message_text = "Det går inte att låna tidskrifter.";
	END IF;
END##


-- FUNCTIONS

CREATE FUNCTION udfGetDueDate (barcode INT)
RETURNS DATE
READS SQL DATA
BEGIN
	DECLARE v_dueDate DATE;
    DECLARE v_loanPeriod INT;
    SET v_loanPeriod = (SELECT loanPeriod FROM category WHERE category.id = (SELECT categoryID FROM copy WHERE copy.barcode = barcode));
    SET v_dueDate = DATE_ADD(now(), INTERVAL v_loanPeriod DAY);
    RETURN v_dueDate;
END ##

CREATE FUNCTION udfBookInActiveLoan (barcode INT)
RETURNS BOOL
READS SQL DATA
BEGIN
    IF (SELECT id FROM loan WHERE loan.barcode = barcode AND loan.returnDate IS NULL) IS NULL
    THEN RETURN FALSE;
    ELSE RETURN TRUE;
    END IF;
END ##


-- PROCEDURES

CREATE PROCEDURE makeLoan(uID INT, bCode INT)
BEGIN
	IF udfBookInActiveLoan(bCode)
		THEN SIGNAL sqlstate '45000' set message_text = "Objektet är redan utlånat.";
	ELSEIF (SELECT barcode FROM copy WHERE copy.barcode = bCode) IS NULL
		THEN SIGNAL sqlstate '45000' set message_text = "Steckkoden finns inte i systemet.";
	ELSE
		INSERT INTO loan (userID, barcode, dueDate) VALUES
			(uID, bCode, udfGetDueDate(bCode));
	END IF;
END ##

-- Uppdaterar returnDate i Loan (Om boken är utlånad).
CREATE PROCEDURE returnLoan(bCode INT)
BEGIN
	DECLARE v_id INT;
	IF udfBookInActiveLoan(bCode)
		THEN
        SET v_id = (SELECT id FROM loan WHERE returnDate IS NULL AND barcode = bCode);
        UPDATE loan
		SET returnDate = now() WHERE id = v_id;
    ELSE
		SIGNAL sqlstate '45000' set message_text = "Objektet är inte utlånat.";
    END IF;
END ##


-- SÖKNINGAR

-- Söker böcker baserat på: ITEM title, isbn. AUTHOR firstname, lastname. CLASSIFICATION classificationName.
CREATE PROCEDURE searchBook(inputText VARCHAR(100))
BEGIN
	SELECT * FROM (
	SELECT item.id, title, subtitle, yearPublished, language, mediaType, isbn FROM item
		WHERE LOWER(title) LIKE LOWER(inputText)
        OR LOWER(subtitle) LIKE LOWER(inputText)
        OR LOWER(yearPublished) LIKE LOWER(inputText)
        OR LOWER(language) LIKE LOWER(inputText)
        OR LOWER(isbn) LIKE LOWER(inputText)
    UNION
	SELECT item.id, title, subtitle, yearPublished, language, mediaType, isbn FROM author
		JOIN itemauthor AS ia ON author.id = ia.authorID
		JOIN item ON ia.itemID = item.id
		WHERE LOWER(author.authorName) LIKE LOWER(inputText)
    UNION
    SELECT item.id, title, subtitle, yearPublished, language, mediaType, isbn FROM classification
		JOIN itemclassification AS ic ON classification.id = ic.classificationID
		JOIN item ON item.id = ic.itemID
		WHERE LOWER(classification.classificationName) LIKE LOWER(inputText)
	) as bookTable WHERE mediaType = 'Bok';
END ##

-- Söker filmer baserat på: ITEM title, subtitle. AUTHOR(regissör) firstname, lastname. CLASSIFICATION classificationName. ACTOR actorName.
CREATE PROCEDURE searchMovie(inputText VARCHAR(100))
BEGIN
	SELECT * FROM (
    SELECT item.id, title, subtitle, yearPublished, language, ageLimit, country, mediaType FROM item
		WHERE LOWER(title) LIKE LOWER(inputText)
        OR LOWER(subtitle) LIKE LOWER(inputText)
        OR LOWER(yearPublished) LIKE LOWER(inputText)
        OR LOWER(language) LIKE LOWER(inputText)
        OR LOWER(ageLimit) LIKE LOWER(inputText)
        OR LOWER(country) LIKE LOWER(inputText)
    UNION
	SELECT item.id, title, subtitle, yearPublished, language, ageLimit, country, mediaType FROM author
		JOIN itemauthor AS ia ON author.id = ia.authorID
		JOIN item ON ia.itemID = item.id
		WHERE LOWER(author.authorName) LIKE LOWER(inputText)
    UNION
    SELECT item.id, title, subtitle, yearPublished, language, ageLimit, country, mediaType FROM classification
		JOIN itemclassification AS ic ON classification.id = ic.classificationID
		JOIN item ON item.id = ic.itemID
		WHERE LOWER(classification.classificationName) LIKE LOWER(inputText)
	UNION
    SELECT item.id, title, subtitle, yearPublished, language, ageLimit, country, mediaType FROM actor
		JOIN itemActor AS ia ON actor.id = ia.actorID
        JOIN item ON item.id = ia.itemID
        WHERE LOWER(actor.actorName) Like LOWER(inputText)
	) AS movieTable WHERE mediaType = 'Film';
END ##

-- Söker tidskrifter baserat på: ITEM title, subtitle, issn. CLASSIFICATION classificationName.
CREATE PROCEDURE searchJournal(inputText VARCHAR(100))
BEGIN
	SELECT * FROM (
    SELECT item.id, title, subtitle, yearPublished, language, mediaType, issn FROM item
		WHERE LOWER(title) LIKE LOWER(inputText)
        OR LOWER(subtitle) LIKE LOWER(inputText)
        OR LOWER(yearPublished) LIKE LOWER(inputText)
        OR LOWER(language) LIKE LOWER(inputText)
        OR LOWER(issn) LIKE LOWER(inputText)
    UNION
    SELECT item.id, title, subtitle, yearPublished, language, mediaType, issn FROM classification
		JOIN itemclassification AS ic ON classification.id = ic.classificationID
		JOIN item ON item.id = ic.itemID
		WHERE LOWER(classification.classificationName) LIKE LOWER(inputText)
	) AS journalTable WHERE mediaType = 'Tidskrift';
END ##

DELIMITER ;

--
-- POPULERING
--

INSERT INTO item (title, subtitle, yearPublished, mediaType, language, isbn, ageLimit, country, issn) VALUES
	("The Lord of the Rings", "The Fellowship of the Ring", "1954", "Bok", "en", "1000000000001", DEFAULT, NULL, DEFAULT),
	("The Lord of the Rings", "The Two Towers", "1954","Bok", "en", "1000000000002", DEFAULT, NULL, DEFAULT),
    ("The Lord of the Rings", "The Return of the King", "1955", "Bok", "en", "1000000000003", DEFAULT, NULL, DEFAULT),
    ("Den Förlorade Symbolen","Robert Langdon", "2009", "Bok", "sv", "2000000000000", DEFAULT, NULL, DEFAULT),
	("The Kingkiller Chronicle","The Name of the Wind", "2007", "Bok", "en", "3000000000001", DEFAULT, NULL, DEFAULT),
	("The Kingkiller Chronicle","The Wise Man''s Fear", "2011", "Bok", "en",  "3000000000002", DEFAULT, NULL, DEFAULT),
	("The Kingkiller Chronicle", "The Doors of Stone", "2022", "Bok", "en",  "3000000000003", DEFAULT, NULL, DEFAULT),
	("Pokemon", "Mewtwo slår tillbaka", "1998", "Film", "sv", NULL, "0", "Japan", DEFAULT),
    ("Ponyo","Gake no ue no Ponyo", "2008", "Film", "jp", NULL, "12", "Japan", DEFAULT),
	("Django Unchained", DEFAULT, "2012", "Film", "en", NULL, "15", "USA", DEFAULT),
    ("Kalle Anka & Co", "Nr 2", "2018", "Tidskrift", "sv", NULL, DEFAULT, NULL, "23456789"),
    ("Bamse", "Nr 18", "2006", "Tidskrift", "sv", NULL, DEFAULT, NULL, "34567891"),
    ("Illustrerad vetenskap", "Nr 5", "2002", "Tidskrift", "sv", NULL, DEFAULT, NULL, "45678912")
    ;
INSERT INTO author (authorName) VALUES
    ("J.R.R. Tolkien"),
	("Dan Brown"),
    ("Patrick Rothfuss"),
    ("Pikachu Ash"),
    ("Hayao Miyazaki"),
    ("Quentin Tarantino"),
	("Axel Pro"),
	("Wiktoria Pro"),
	("Teodor Pro"),
	("Robin Hood");
INSERT INTO itemauthor (itemID, authorID) VALUES
	(1, 1),
    (2, 1),
    (3, 1),
    (4, 2),
    (5, 3),
    (6, 3),
    (7, 3),
    (8, 4),
    (9, 5),
	(10, 6);
INSERT INTO classification (classificationName) VALUES
	("fantasy"),
	("coolt"),
	("alver"),
	("sauron"),
	("thriller"),
	("mysterie"),
	("anime"),
	("tecknat"),
    ("blod"),
    ("mord"),
    ("elende"),
    ("vetenskap");
INSERT INTO itemClassification (itemID, classificationID) VALUES
	(1,1), (1,2), (1,3), (1,4),
	(2,1), (2,2), (2,3), (2,4),
	(3,1), (3,2), (3,3), (3,4),
	(4,5), (4,6),
	(5,1),
	(6,1),
	(7,1),
	(8,7), (8,8),
	(9,8),
	(10,9), (10,10), (10,11),
    (11,8),
    (12,8),
    (13,12);
INSERT INTO actor (actorName) VALUES
    ("Ash Ketchum"),
    ("Pikachu"),
    ("Mewtwo"),
	("Ponyo"),
    ("Soske"),
    ("Jamie Foxx"),
    ("Leonardo DiCaprio"),
    ("Kerry Washington");
INSERT INTO itemActor (itemID, actorID) VALUES
	(8, 1), (8, 2), (8, 3),
    (9, 4), (9, 5),
    (10, 6), (10, 7), (10, 8);
INSERT INTO category (categoryName, loanPeriod) VALUES
    ("Standard", 30),
    ("Kurslitteratur", 14),
    ("Film", 7),
    ("Tidskrift", 0),
    ("Referenslitteratur", 0);
INSERT INTO copy (barcode, itemID, location, categoryID) VALUES
	(001,1,"Hylla 1",1),
    (002,1,"Hylla 1",1),
	(003,1,"Hylla R",1),
	(004,2,"Hylla 1",1),
	(005,2,"Hylla R",5),
	(006,3,"Hylla 2",1),
	(007,3,"Hylla R",2),
	(008,4,"Hylla 1",2),
	(009,4,"Hylla 1",2),
	(010,5,"Hylla 1",1),
	(011,5,"Hylla 2",1),
	(012,6,"Hylla 1",1),
	(013,6,"Hylla 1",1),
	(014,7,"Hylla R",2),
	(015,7,"Hylla R",2),
	(016,8,"Hylla 9",3),
	(017,8,"Hylla 9",3),
	(018,8,"Hylla 9",3),
	(019,9,"Hylla 9",3),
	(020,9,"Hylla 9",3),
	(021,9,"Hylla 9",3),
	(022,10,"Hylla 9",3),
	(023,11,"Hylla 18",4),
	(024,12,"Hylla S",4),
	(025,13,"Hylla 5",4);
INSERT INTO userType (userTypeName, maxNumberOfLoans) VALUES
	 ('Allmän', 5),
     ('Student', 5),
     ('Anställd', 10),
     ('Forskare', 20),
     ('Admin', 0);
INSERT INTO user (userTypeID, firstName, lastName, idNumber, eMail, pinCode) VALUES
	(5,"Admin","PRO",133333333337,"admin.pro@best.com",1111),
	(1,"Gil","Knowles",200188910268,"justo.sit.amet@protonmail.ca",6685),
	(1,"Kieran","Warner",199231449700,"porttitor.tellus@aol.couk",3712),
	(1,"Walker","Holman",200632510100,"ipsum.sodales@protonmail.ca",6366),
	(2,"Signe","Edwards",199295760527,"tempus@hotmail.couk",4906),
	(2,"Vanna","Stanton",200658698142,"vitae.diam.proin@hotmail.edu",7710),
	(2,"Illiana","Schneider",200572321533,"adipiscing.ligula@aol.org",9882),
	(3,"Forrest","Church",199930336481,"placerat.eget@hotmail.ca",1707),
	(3,"Kylie","Alvarez",201105271435,"erat.eget@outlook.edu",7424),
	(4,"Nigel","Maxwell",200502289210,"imperdiet.non@aol.com",3204);

CALL makeLoan(2, 4);
CALL makeLoan(2, 6);
CALL makeLoan(2, 8);
-- Försenade lån
INSERT INTO loan (userID, barcode, startDate, returnDate, dueDate) values
    (10, 22, '2022-05-01 10:00:00', null, '2022-05-02'),
    (10, 10, '2022-05-01 10:00:00', null, '2022-05-02');